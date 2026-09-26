import SwiftUI

struct CountryPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var countries: [(code: String, name: String)] {
        Locale.Region.isoRegions
            .map { ($0.identifier, Locale.current.localizedString(forRegionCode: $0.identifier) ?? $0.identifier) }
            .filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) || $0.1.localizedCaseInsensitiveContains(search) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RELEASE COUNTRY")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.8)

            Text("Only editions released in this country are shown.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            NativeActionButton("Use My Location") {
                model.useCurrentLocation()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Use My Location")
                    Spacer()
                    if model.countryOverride == nil { Image(systemName: "checkmark") }
                }
                .padding(10)
            }
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            Text(model.countryOverride == nil
                 ? (model.countrySource == .location ? "Using current location · \(model.releaseCountryName)" : "Using Mac region · \(model.releaseCountryName)")
                 : "Manually selected · \(model.releaseCountryName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search countries", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(countries, id: \.code) { country in
                        NativeActionButton("Select \(country.name)") {
                            model.chooseCountry(country.code)
                            dismiss()
                        } label: {
                            HStack {
                                Text(country.name)
                                Spacer()
                                Text(country.code)
                                    .foregroundStyle(.secondary)
                                if model.countryOverride == country.code {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .frame(height: 240)
        }
        .padding(18)
        .frame(width: 320)
    }
}
