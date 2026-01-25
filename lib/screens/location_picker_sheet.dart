import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_location.dart';
import '../services/places_autocomplete_service.dart';
import '../state/location_store.dart';
import '../utils/geo.dart';
import 'theme.dart';

class LocationPickerSheet extends StatefulWidget {
  final LocationStore locationStore;

  const LocationPickerSheet({super.key, required this.locationStore});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  static const double _centerLat = 48.137154;
  static const double _centerLng = 11.576124;
  static const double _maxDistanceKm = 30;

  final TextEditingController _controller = TextEditingController();
  final PlacesAutocompleteService _service = PlacesAutocompleteService();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  bool _isLoading = false;
  bool _isResolving = false;
  List<PlaceSuggestion> _suggestions = [];
  String? _suggestionError;
  late final String _sessionToken;

  @override
  void initState() {
    super.initState();
    _sessionToken = _service.newSessionToken();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(value);
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    if (input.trim().isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final results = await _service.fetchSuggestions(
      input: input.trim(),
      sessionToken: _sessionToken,
    );
    if (!mounted) return;
    setState(() {
      _suggestions = results.take(5).toList();
      _suggestionError = _service.lastErrorMessage;
      _isLoading = false;
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _isResolving = true;
    });
    final latLng = await _service.fetchLatLng(
      placeId: suggestion.placeId,
      sessionToken: _sessionToken,
    );
    if (!mounted) return;
    if (latLng != null) {
      if (_isWithinServiceArea(latLng.lat, latLng.lng)) {
        widget.locationStore.setManualLocation(
          AppLocation(
            label: _formatLocationLabel(suggestion),
            lat: latLng.lat,
            lng: latLng.lng,
            source: AppLocationSource.manual,
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      widget.locationStore.setManualLocation(
        const AppLocation(
          label: 'München Zentrum',
          lat: _centerLat,
          lng: _centerLng,
          source: AppLocationSource.fallback,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nur im Umkreis von 30 km um München verfügbar.'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isResolving = false;
    });
  }

  String _formatLocationLabel(PlaceSuggestion suggestion) {
    final secondary = suggestion.secondaryText.trim();
    if (secondary.isNotEmpty) {
      final parts = secondary
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) {
        final first = parts.first;
        if (first.contains('-')) {
          final split = first
              .split('-')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
          if (split.length >= 2) {
            return '${split.first} ${split.sublist(1).join('-')}';
          }
        }
        return first;
      }
    }
    return suggestion.mainText.trim();
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.of(context).size.height * 0.85;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final selected = widget.locationStore.currentLocation;
    final isManual = selected.source == AppLocationSource.manual;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: MingaTheme.borderStrong,
                  borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Standort auswählen',
                      style: MingaTheme.titleLarge.copyWith(
                        color: MingaTheme.textPrimary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: MingaTheme.glassOverlayXXSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: MingaTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: MingaTheme.glassOverlayXXSoft,
                  borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _searchFocus,
                  onChanged: _onChanged,
                  style: MingaTheme.body,
                  decoration: InputDecoration(
                    hintText: 'Ort, Stadtteil oder Straße suchen',
                    hintStyle: MingaTheme.bodySmall.copyWith(
                      color: MingaTheme.textSubtle,
                    ),
                    prefixIcon:
                        Icon(Icons.search, color: MingaTheme.textSecondary),
                    filled: true,
                    fillColor: MingaTheme.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 14),
              _buildActionRow(
                icon: Icons.my_location,
                label: 'Aktuellen Standort verwenden',
                accent: true,
                onTap: _isResolving
                    ? null
                    : () async {
                        await widget.locationStore.useMyLocation();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                trailing: isManual
                    ? null
                    : Icon(
                        Icons.check,
                        size: 16,
                        color: MingaTheme.accentGreen,
                      ),
              ),
              if (isManual) ...[
                SizedBox(height: 6),
                _buildActionRow(
                  icon: Icons.place_outlined,
                  label: 'Ausgewählter Standort · ${selected.label}',
                  onTap: null,
                  trailing: Icon(
                    Icons.check,
                    size: 16,
                    color: MingaTheme.accentGreen,
                  ),
                ),
              ],
              SizedBox(height: 8),
              Expanded(child: _buildSuggestionsBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: MingaTheme.accentGreen,
        ),
      );
    }
    if (_suggestionError != null && _controller.text.trim().isNotEmpty) {
      return Center(
        child: Text(
          _suggestionError!,
          style: MingaTheme.bodySmall.copyWith(
            color: MingaTheme.textSubtle,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_suggestions.isEmpty) {
      return Center(
        child: Text(
          'Keine Vorschläge',
          style: MingaTheme.bodySmall.copyWith(
            color: MingaTheme.textSubtle,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) =>
          Divider(color: MingaTheme.borderSubtle, height: 1),
      itemBuilder: (context, index) {
        final suggestion = _suggestions[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          dense: true,
          visualDensity: VisualDensity.compact,
          onTap:
              _isResolving ? null : () => _selectSuggestion(suggestion),
          leading: Icon(
            Icons.place_outlined,
            size: 18,
            color: MingaTheme.textSubtle,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                suggestion.mainText,
                style: MingaTheme.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (suggestion.secondaryText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    suggestion.secondaryText,
                    style: MingaTheme.bodySmall.copyWith(
                      color: MingaTheme.textSubtle,
                    ),
                  ),
                ),
            ],
          ),
          trailing: _isResolving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MingaTheme.accentGreen,
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool accent = false,
    Widget? trailing,
  }) {
    final iconColor = accent ? MingaTheme.accentGreen : MingaTheme.textSecondary;
    final textColor = accent ? MingaTheme.accentGreen : MingaTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MingaTheme.glassOverlayXXSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: MingaTheme.body.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  bool _isWithinServiceArea(double lat, double lng) {
    final distance = haversineDistanceKm(lat, lng, _centerLat, _centerLng);
    return distance <= _maxDistanceKm;
  }
}

