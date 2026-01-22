import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_location.dart';
import '../services/places_autocomplete_service.dart';
import '../state/location_store.dart';
import 'theme.dart';

class LocationPickerSheet extends StatefulWidget {
  final LocationStore locationStore;

  const LocationPickerSheet({super.key, required this.locationStore});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final PlacesAutocompleteService _service = PlacesAutocompleteService();
  Timer? _debounce;
  bool _isLoading = false;
  bool _isResolving = false;
  List<PlaceSuggestion> _suggestions = [];
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
      _suggestions = results;
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
      widget.locationStore.setManualLocation(
        AppLocation(
          label: suggestion.mainText,
          lat: latLng.lat,
          lng: latLng.lng,
          source: AppLocationSource.manual,
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isResolving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: MingaTheme.borderStrong,
                borderRadius: BorderRadius.circular(MingaTheme.radiusSm),
              ),
            ),
            GlassSurface(
              radius: 14,
              blurSigma: 16,
              overlayColor: MingaTheme.glassOverlayXSoft,
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                style: MingaTheme.body,
                decoration: InputDecoration(
                  hintText: 'Ort oder Stadtteil suchen',
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
                ),
              ),
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isResolving
                    ? null
                    : () async {
                        await widget.locationStore.useMyLocation();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                icon: Icon(
                  Icons.my_location,
                  color: MingaTheme.accentGreen,
                  size: 18,
                ),
                label: Text(
                  'Use my location',
                  style: MingaTheme.body.copyWith(
                    color: MingaTheme.accentGreen,
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),
            if (_isLoading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(
                  color: MingaTheme.accentGreen,
                ),
              )
            else if (_suggestions.isEmpty)
              Text(
                'Keine Vorschläge',
              style: MingaTheme.bodySmall.copyWith(
                color: MingaTheme.textSubtle,
              ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(color: MingaTheme.borderSubtle, height: 1),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    onTap: _isResolving
                        ? null
                        : () => _selectSuggestion(suggestion),
                    title: Text(
                      suggestion.mainText,
                      style: MingaTheme.body,
                    ),
                    subtitle: suggestion.secondaryText.isNotEmpty
                        ? Text(
                            suggestion.secondaryText,
                            style: MingaTheme.bodySmall.copyWith(
                              color: MingaTheme.textSubtle,
                            ),
                          )
                        : null,
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
              ),
          ],
        ),
      ),
    );
  }
}

