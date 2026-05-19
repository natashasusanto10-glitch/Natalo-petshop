import 'dart:async';

import 'package:flutter/material.dart';

import '../services/places_service.dart';

/// Inline address autocomplete field — user ngetik di sini, suggestion
/// dropdown muncul real-time di bawah field (pattern Tokopedia/Shopee/Gojek).
///
/// Implementation:
/// - `CompositedTransformTarget` + `LayerLink` anchor untuk Overlay
/// - Debounce 350ms saat user ngetik → call `placesService.autocomplete`
/// - Min 3 chars sebelum query (sama dengan Google Places API rule)
/// - Tap suggestion → `placesService.details` → callback `onSelected`
///   bawa PlaceDetails lengkap (formattedAddress, postal, city, dst.)
/// - Loading state di-show via `loading` indicator small di trailing
///
/// Caller responsibility:
/// - Pass `controller` untuk text input (form integration)
/// - Implement `onSelected(PlaceDetails)` untuk fill field lain di form
/// - Optional `validator` untuk form validation
class AddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final void Function(PlaceDetails details) onSelected;
  final FormFieldValidator<String>? validator;
  final int maxLines;

  const AddressAutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    required this.onSelected,
    this.hint = 'Mis. Jl. MT. Haryono No. 103',
    this.validator,
    this.maxLines = 2,
  });

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  OverlayEntry? _overlay;

  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  bool _fetchingDetails = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocusChange);
    _focus.dispose();
    _debounce?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focus.hasFocus) {
      // Delay sedikit supaya tap suggestion tetap ke-handle sebelum overlay
      // di-remove. 200ms cukup untuk ListTile onTap fire.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_focus.hasFocus) _removeOverlay();
      });
    } else if (_suggestions.isNotEmpty) {
      _showOverlay();
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    final trimmed = query.trim();
    if (trimmed == _lastQuery) return;
    _lastQuery = trimmed;
    setState(() => _searching = true);
    try {
      final results = await placesService.autocomplete(query: trimmed);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
      if (results.isNotEmpty) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _pickSuggestion(PlaceSuggestion suggestion) async {
    _removeOverlay();
    setState(() => _fetchingDetails = true);
    try {
      final details = await placesService.details(placeId: suggestion.placeId);
      if (!mounted) return;
      if (details != null) {
        // Pre-fill controller dengan formattedAddress sebelum callback —
        // supaya field langsung update walau parent callback async.
        widget.controller.text = details.formattedAddress;
        widget.onSelected(details);
        _focus.unfocus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal ambil detail alamat. Coba lagi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingDetails = false);
    }
  }

  void _showOverlay() {
    _removeOverlay();
    if (_suggestions.isEmpty) return;

    _overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _link.leaderSize?.width ?? 320,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            // Anchor di bawah field — offset Y = field height.
            // Field height ~80 (label + textfield + padding) — ambil
            // dari _link.leaderSize kalau ada.
            offset: Offset(0, (_link.leaderSize?.height ?? 72) + 4),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              shadowColor: Colors.black.withValues(alpha: 0.15),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 1,
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: Color(0xFFF1F5F9),
                        indent: 12,
                        endIndent: 12,
                      ),
                      itemBuilder: (context, index) {
                        final s = _suggestions[index];
                        return InkWell(
                          onTap: () => _pickSuggestion(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  size: 18,
                                  color: Color(0xFF0B7FEA),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        s.mainText ?? s.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF111827),
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                          height: 1.3,
                                        ),
                                      ),
                                      if (s.secondaryText != null &&
                                          s.secondaryText!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            s.secondaryText!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF6B7280),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        validator: widget.validator,
        maxLines: widget.maxLines,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: const Icon(
            Icons.location_on_outlined,
            color: Color(0xFF9CA3AF),
          ),
          suffixIcon: (_searching || _fetchingDetails)
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
