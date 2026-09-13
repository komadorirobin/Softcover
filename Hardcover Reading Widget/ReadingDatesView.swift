import SwiftUI

struct ReadingDatesView: View {
    let userBookId: Int
    let editionId: Int?
    
    @Environment(\.dismiss) private var dismiss
    @State private var readingDates: [HardcoverService.ReadingDate] = []
    @State private var isLoading = true
    @State private var showAddDatePicker = false
    @State private var editingRead: HardcoverService.ReadingDate?
    @State private var pendingDelete: HardcoverService.ReadingDate?
    @State private var errorMessage: String?
    @State private var loadGeneration = UUID()
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
    
    var body: some View {
        NavigationStack {
            List {
                if let error = errorMessage {
                    InlineLoadError(message: error) { Task { await loadReadingDates() } }
                }
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    Section {
                        Button {
                            showAddDatePicker = true
                        } label: {
                            Label("Add New Read", systemImage: "plus.circle.fill")
                        }
                    }
                    
                    if !readingDates.isEmpty {
                        Section {
                            ForEach(readingDates) { read in
                                ReadingDateRow(
                                    read: read,
                                    onEdit: { editRead(read) },
                                    onDelete: { pendingDelete = read }
                                )
                            }
                        } header: {
                            Text("Reading History")
                        }
                    }
                }
            }
            .navigationTitle("Dates Read")
            .confirmationDialog("Delete reading date?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                if let read = pendingDelete { Button("Delete", role: .destructive) { deleteRead(read) } }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadReadingDates()
            }
            .sheet(isPresented: $showAddDatePicker) {
                DatePickerSheet(
                    userBookId: userBookId,
                    editionId: editionId,
                    onComplete: {
                        showAddDatePicker = false
                        Task { await loadReadingDates() }
                    }
                )
            }
            .sheet(item: $editingRead) { read in
                EditDatePickerSheet(
                    userBookId: userBookId,
                    editionId: editionId,
                    read: read,
                    onComplete: {
                        editingRead = nil
                        Task { await loadReadingDates() }
                    }
                )
            }
        }
    }
    
    @MainActor private func loadReadingDates() async {
        let token = UUID(), account = HardcoverConfig.authorizationHeaderValue
        loadGeneration = token
        isLoading = readingDates.isEmpty
        errorMessage = nil
        defer { if loadGeneration == token { isLoading = false } }
        do {
            let dates = try await HardcoverReadScope.checked { await HardcoverService.fetchReadingDates(userBookId: userBookId) }
            guard token == loadGeneration, account == HardcoverConfig.authorizationHeaderValue else { return }
            readingDates = dates
        } catch is CancellationError { }
        catch { if token == loadGeneration, account == HardcoverConfig.authorizationHeaderValue { errorMessage = error.localizedDescription } }
    }
    
    private func editRead(_ read: HardcoverService.ReadingDate) {
        print("📝 Opening edit sheet for read: \(read.id)")
        editingRead = read
    }
    
    private func deleteRead(_ read: HardcoverService.ReadingDate) {
        Task {
            let account = HardcoverConfig.authorizationHeaderValue
            do {
                let success = try await HardcoverReadScope.checked { await HardcoverService.deleteReadingDate(readId: read.id) }
                guard account == HardcoverConfig.authorizationHeaderValue else { return }
                guard success else { throw HardcoverNetworkError.invalidResponse }
                WidgetSync.libraryChanged(statuses: [2, 3])
                await loadReadingDates()
            } catch { if account == HardcoverConfig.authorizationHeaderValue { errorMessage = error.localizedDescription } }
            pendingDelete = nil
        }
    }
}

struct ReadingDateRow: View {
    let read: HardcoverService.ReadingDate
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let startDate = read.startDate {
                        HStack(spacing: 6) {
                            Image(systemName: "book.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Started: \(dateFormatter.string(from: startDate))")
                                .font(.subheadline)
                        }
                    }
                    
                    if let endDate = read.endDate {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Finished: \(dateFormatter.string(from: endDate))")
                                .font(.subheadline)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("In progress")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct DatePickerSheet: View {
    let userBookId: Int
    let editionId: Int?
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    @State private var currentReadId: Int?
    @State private var startDateString: String?
    @State private var isPickingEndDate = false
    @State private var isSaving = false
    @State private var hasSelectedStartDate = false
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                } else {
                    VStack(spacing: 12) {
                        Text(isPickingEndDate ? LocalizedStringKey("Select End Date") : LocalizedStringKey("Select Start Date"))
                            .font(.headline)
                        
                        if isPickingEndDate {
                            Text("Select when you finished reading, then tap Confirm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Tap a date to mark when you started reading")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top)
                    
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    
                    if isPickingEndDate {
                        Button {
                            Task {
                                await handleEndDateConfirmation()
                            }
                        } label: {
                            Text("Confirm End Date")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Add New Read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onComplete()
                    }
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                if !isPickingEndDate && !hasSelectedStartDate {
                    // First selection: automatically set start date
                    hasSelectedStartDate = true
                    Task {
                        await handleStartDateSelection(newDate)
                    }
                }
            }
        }
    }
    
    private func handleStartDateSelection(_ date: Date) async {
        print("📅 handleStartDateSelection called - date: \(date)")
        guard !isSaving else {
            print("⏸️ Already saving, ignoring click")
            return
        }
        
        await MainActor.run { isSaving = true }
        
        let dateString = dateFormatter.string(from: date)
        print("📅 Date string: \(dateString)")
        print("🎯 Creating new read with start date...")
        
        if let readId = await HardcoverService.insertReadingDate(
            userBookId: userBookId,
            startedAt: dateString,
            editionId: editionId
        ) {
            print("✅ Got readId: \(readId), switching to end date picker")
            await MainActor.run {
                currentReadId = readId
                startDateString = dateString  // Save the start date
                isPickingEndDate = true
                isSaving = false
            }
        } else {
            print("❌ Failed to insert reading date")
            await MainActor.run { isSaving = false }
        }
    }
    
    private func handleEndDateConfirmation() async {
        print("📅 handleEndDateConfirmation called")
        guard !isSaving else {
            print("⏸️ Already saving, ignoring click")
            return
        }
        
        await MainActor.run { isSaving = true }
        
        let dateString = dateFormatter.string(from: selectedDate)
        print("📅 End date string: \(dateString)")
        print("🎯 Setting end date for readId: \(currentReadId ?? -1)")
        
        if let readId = currentReadId {
            // First, get the current read to preserve the start date
            let reads = await HardcoverService.fetchReadingDates(userBookId: userBookId)
            let currentRead = reads.first(where: { $0.id == readId })
            let preservedStartDate = currentRead?.startedAt ?? startDateString
            
            print("📅 Preserving start date: \(preservedStartDate ?? "nil")")
            
            let success = await HardcoverService.updateReadingDate(
                readId: readId,
                startedAt: preservedStartDate,  // Include the start date!
                finishedAt: dateString,
                editionId: editionId
            )
            print(success ? "✅ Successfully updated with end date" : "❌ Failed to update with end date")
            await MainActor.run {
                isSaving = false
                if success {
                    print("✅ Dismissing sheet and calling onComplete")
                    dismiss()
                    onComplete()
                }
            }
        } else {
            print("❌ No currentReadId available")
            await MainActor.run { isSaving = false }
        }
    }
}

struct EditDatePickerSheet: View {
    let userBookId: Int
    let editionId: Int?
    let read: HardcoverService.ReadingDate
    let onComplete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var endDate: Date?
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    
    init(userBookId: Int, editionId: Int?, read: HardcoverService.ReadingDate, onComplete: @escaping () -> Void) {
        self.userBookId = userBookId
        self.editionId = editionId
        self.read = read
        self.onComplete = onComplete
        
        // Initialize state with current values
        _startDate = State(initialValue: read.startDate ?? Date())
        _endDate = State(initialValue: read.endDate)
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        return df
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }
                
                Section {
                    Toggle("Has finished reading", isOn: Binding(
                        get: { endDate != nil },
                        set: { isOn in
                            if isOn && endDate == nil {
                                endDate = Date()
                            } else if !isOn {
                                endDate = nil
                            }
                        }
                    ))
                    
                    if endDate != nil {
                        DatePicker(
                            "End Date",
                            selection: Binding(
                                get: { endDate ?? Date() },
                                set: { endDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete This Read", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Delete Read", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteRead()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this reading record?")
            }
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.2)
                        ProgressView()
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                    }
                }
            }
        }
    }
    
    private func saveChanges() async {
        await MainActor.run { isSaving = true }
        
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = endDate.map { dateFormatter.string(from: $0) }
        
        print("📝 Editing read \(read.id): start=\(startDateString), end=\(endDateString ?? "nil")")
        
        let success = await HardcoverService.updateReadingDate(
            readId: read.id,
            startedAt: startDateString,
            finishedAt: endDateString,
            editionId: editionId
        )
        
        await MainActor.run {
            isSaving = false
            if success {
                print("✅ Successfully updated read")
                dismiss()
                onComplete()
            } else {
                print("❌ Failed to update read")
            }
        }
    }
    
    private func deleteRead() async {
        await MainActor.run { isSaving = true }
        
        let success = await HardcoverService.deleteReadingDate(readId: read.id)
        
        await MainActor.run {
            isSaving = false
            if success {
                print("✅ Successfully deleted read")
                dismiss()
                onComplete()
            } else {
                print("❌ Failed to delete read")
            }
        }
    }
}

#Preview {
    ReadingDatesView(userBookId: 123, editionId: 456)
}
