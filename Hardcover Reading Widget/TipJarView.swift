import SwiftUI
import StoreKit

/// A tip jar view using StoreKit 2 that lets users leave a tip to support development.
struct TipJarView: View {
    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var purchasedTip: Product?
    @State private var showThankYou = false

    /// Consumable product IDs — must match App Store Connect exactly.
    static let productIDs: [String] = [
        "komadori.softcover.tip.small",
        "komadori.softcover.tip.medium",
        "komadori.softcover.tip.large"
    ]

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

                    Text("Softcover is free and always will be. If you enjoy using it, a small tip helps keep development going. Thank you! ❤️")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading tips…")
                        Spacer()
                    }
                    .padding()
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(products.sorted(by: { $0.price < $1.price })) { product in
                        TipRow(product: product, meta: tipMeta[product.id]) {
                            await purchase(product)
                        }
                    }
                }
            }

            Section {
                Text("Tips are one-time purchases. Apple processes the payment. Thank you for your generosity!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Tip Jar")
        .task { await loadProducts() }
        .alert("Thank you! 🎉", isPresented: $showThankYou) {
            Button("OK", role: .cancel) { }
        } message: {
            if let tip = purchasedTip {
                Text("Your \(tip.displayName) means a lot. Thanks for supporting Softcover!")
            }
        }
    }

    // MARK: - StoreKit 2

    private func loadProducts() async {
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            await MainActor.run {
                products = fetched
                isLoading = false
                if fetched.isEmpty {
                    errorMessage = "No tip options available right now."
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Could not load tips. Please try again later."
            }
        }
    }

    private func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    // Consumable — finish immediately
                    await transaction.finish()
                    await MainActor.run {
                        purchasedTip = product
                        showThankYou = true
                    }
                }
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            print("Purchase error: \(error)")
        }
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
