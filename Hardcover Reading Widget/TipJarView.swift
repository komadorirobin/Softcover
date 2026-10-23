import SwiftUI
import StoreKit
import UIKit
import WidgetKit

/// A small monetization experiment: a lifetime supporter unlock plus optional tips.
struct TipJarView: View {
    @StateObject private var store = SupporterStore()
    @State private var purchasedProduct: Product?
    @State private var showThankYou = false

    private let tipMeta: [String: (emoji: String, label: String)] = [
        "komadori.softcover.tip.small":  ("☕", "Small Tip"),
        "komadori.softcover.tip.medium": ("🍕", "Medium Tip"),
        "komadori.softcover.tip.large":  ("🎉", "Large Tip"),
    ]

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.pink)

                    Text("Support Softcover")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Every reading feature stays free, including sessions, deadlines, statistics, widgets, and sharing. Supporter purchases only unlock the cosmetic Supporter Collection.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section("Supporter Collection") {
                SupporterCollectionPreview()
            }

            Section("Lifetime unlock") {
                if store.isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading…")
                        Spacer()
                    }
                    .padding()
                } else if store.isSupporter {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("You're a Softcover Supporter")
                                .font(.headline)
                            Text("Your alternate icons, accent palettes, and quote widget themes are unlocked.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                    }
                    .padding(.vertical, 6)
                } else if !store.supporterProducts.isEmpty {
                    Text("Both options unlock exactly the same cosmetic pack. Choose the generous option only if you want to provide extra support.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(store.supporterProducts) { product in
                        SupporterRow(product: product) {
                            if await store.purchase(product) {
                                purchasedProduct = product
                                showThankYou = true
                            }
                        }
                    }
                } else if let error = store.errorMessage {
                    Text(error)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }

                Button("Restore Purchase") {
                    Task { await store.restore() }
                }
                .disabled(store.isRestoring)
            }

            if !store.tipProducts.isEmpty {
                Section("Optional tips") {
                    ForEach(store.tipProducts.sorted(by: { $0.price < $1.price })) { product in
                        TipRow(product: product, meta: tipMeta[product.id]) {
                            if await store.purchase(product) {
                                purchasedProduct = product
                                showThankYou = true
                            }
                        }
                    }
                }
            }

            Section {
                Text("Supporter purchases are one-time, non-consumable cosmetic purchases that can be restored. Both levels unlock the same Supporter Collection. No reading feature is paywalled. Tips are one-time consumable purchases. Apple processes all payments.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Support Softcover")
        .alert("Thank you! 🎉", isPresented: $showThankYou) {
            Button("OK", role: .cancel) { }
        } message: {
            if let product = purchasedProduct {
                Text("Your \(product.displayName) means a lot. Thanks for supporting Softcover!")
            }
        }
        .alert("Could not complete purchase", isPresented: Binding(
            get: { store.purchaseError != nil },
            set: { if !$0 { store.purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) { store.purchaseError = nil }
        } message: {
            Text(store.purchaseError ?? String(localized: "Please try again later."))
        }
    }
}

// MARK: - StoreKit

@MainActor
final class SupporterStore: ObservableObject {
    static let tipProductIDs = [
        "komadori.softcover.tip.small",
        "komadori.softcover.tip.medium",
        "komadori.softcover.tip.large"
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isSupporter = SupporterAccess.isUnlocked
    @Published private(set) var isLoading = true
    @Published private(set) var isRestoring = false
    @Published private(set) var errorMessage: String?
    @Published var purchaseError: String?

    private var transactionUpdates: Task<Void, Never>?

    var supporterProducts: [Product] {
        products
            .filter { SupporterAccess.grantsEntitlement($0.id) }
            .sorted { $0.price < $1.price }
    }

    var tipProducts: [Product] {
        products.filter { Self.tipProductIDs.contains($0.id) }
    }

    init() {
        transactionUpdates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }

        Task { await loadProducts() }
    }

    deinit {
        transactionUpdates?.cancel()
    }

    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = String(localized: "The purchase could not be verified.")
                    return false
                }
                if SupporterAccess.grantsEntitlement(transaction.productID) {
                    setSupporter(true)
                }
                await transaction.finish()
                return true
            case .pending:
                purchaseError = String(localized: "The purchase is waiting for approval.")
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func loadProducts() async {
        do {
            products = try await Product.products(for: SupporterAccess.productIDs + Self.tipProductIDs)
            if products.isEmpty {
                errorMessage = String(localized: "No purchase options are available right now.")
            } else if supporterProducts.isEmpty {
                errorMessage = String(localized: "Supporter options are not available right now.")
            }
        } catch {
            errorMessage = String(localized: "Could not load purchase options. Please try again later.")
        }
        await refreshEntitlement()
        isLoading = false
    }

    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SupporterAccess.grantsEntitlement(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            unlocked = true
            break
        }
        setSupporter(unlocked)
    }

    private func setSupporter(_ unlocked: Bool) {
        let changed = SupporterAccess.isUnlocked != unlocked
        SupporterAccess.isUnlocked = unlocked
        isSupporter = unlocked
        if !unlocked,
           UIApplication.shared.supportsAlternateIcons,
           UIApplication.shared.alternateIconName != nil {
            UIApplication.shared.setAlternateIconName(nil)
        }
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: "QuoteWidget")
        }
    }

    /// Refreshes the shared entitlement on app launch, including after a reinstall,
    /// refund, or purchase made on another device.
    static func refreshSharedEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  SupporterAccess.grantsEntitlement(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            unlocked = true
            break
        }
        let changed = SupporterAccess.isUnlocked != unlocked
        SupporterAccess.isUnlocked = unlocked
        if changed {
            WidgetCenter.shared.reloadTimelines(ofKind: "QuoteWidget")
        }
    }
}

// MARK: - Supporter Row

private struct SupporterRow: View {
    let product: Product
    let onPurchase: () async -> Void

    @State private var isPurchasing = false

    private var isGenerous: Bool {
        product.id == SupporterAccess.generousProductID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Label("4 alternate app icons, 8 quote themes, and 4 accent palettes", systemImage: "paintpalette.fill")
                .font(.subheadline)

            Label("Future cosmetics added to this collection are included", systemImage: "sparkles")
                .font(.subheadline)

            Button {
                isPurchasing = true
                Task {
                    await onPurchase()
                    isPurchasing = false
                }
            } label: {
                if isPurchasing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if isGenerous {
                    Text("Unlock + extra support for \(product.displayPrice)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Unlock for \(product.displayPrice)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(isPurchasing)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Supporter Collection Preview

private struct SupporterCollectionPreview: View {
    private let icons = [
        "AppIconAuroraPreview",
        "AppIconSunsetPreview",
        "AppIconInkPreview",
        "AppIconVellumPreview"
    ]

    private let themes: [(name: LocalizedStringKey, start: Color, end: Color, isLight: Bool)] = [
        ("Aurora", Color(red: 0.08, green: 0.20, blue: 0.22), Color(red: 0.25, green: 0.48, blue: 0.42), false),
        ("Sunset", Color(red: 0.40, green: 0.12, blue: 0.22), Color(red: 0.95, green: 0.42, blue: 0.20), false),
        ("Ink", Color(red: 0.04, green: 0.05, blue: 0.09), Color(red: 0.24, green: 0.20, blue: 0.36), false),
        ("Lavender", Color(red: 0.21, green: 0.13, blue: 0.38), Color(red: 0.62, green: 0.38, blue: 0.76), false),
        ("Ember", Color(red: 0.31, green: 0.07, blue: 0.08), Color(red: 0.87, green: 0.36, blue: 0.10), false),
        ("Moss", Color(red: 0.10, green: 0.19, blue: 0.10), Color(red: 0.42, green: 0.48, blue: 0.18), false),
        ("Moonlight", Color(red: 0.06, green: 0.10, blue: 0.20), Color(red: 0.34, green: 0.47, blue: 0.70), false),
        ("Parchment", Color(red: 0.95, green: 0.86, blue: 0.66), Color(red: 0.73, green: 0.49, blue: 0.27), true)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Alternate app icons", systemImage: "app.dashed")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.14), radius: 3, y: 2)
                }
            }

            Label("Eight extra quote widget themes", systemImage: "quote.bubble.fill")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 10)], spacing: 10) {
                ForEach(Array(themes.enumerated()), id: \.offset) { _, theme in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(
                                colors: [theme.start, theme.end],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 40)
                            .overlay {
                                Image(systemName: "quote.opening")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.isLight ? .black.opacity(0.7) : .white.opacity(0.9))
                            }
                        Text(theme.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Label("Four extra app accent palettes", systemImage: "paintbrush.pointed.fill")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Tip Row

private struct TipRow: View {
    let product: Product
    let meta: (emoji: String, label: String)?
    let onPurchase: () async -> Void

    @State private var isPurchasing = false

    var body: some View {
        HStack(spacing: 14) {
            Text(meta?.emoji ?? "💝")
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.headline)
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                isPurchasing = true
                Task {
                    await onPurchase()
                    isPurchasing = false
                }
            } label: {
                if isPurchasing {
                    ProgressView()
                        .frame(width: 70)
                } else {
                    Text(product.displayPrice)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationView {
        TipJarView()
    }
}
