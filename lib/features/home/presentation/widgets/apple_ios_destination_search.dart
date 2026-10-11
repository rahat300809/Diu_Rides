import 'package:flutter/material.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';

class AppleIosDestinationSearch extends StatefulWidget {
  final List<RideModel> allRides;
  final String currentQuery;
  final Function(String query) onQueryChanged;
  final Function(String destination) onDestinationSelected;
  final VoidCallback onClear;

  const AppleIosDestinationSearch({
    super.key,
    required this.allRides,
    required this.currentQuery,
    required this.onQueryChanged,
    required this.onDestinationSelected,
    required this.onClear,
  });

  @override
  State<AppleIosDestinationSearch> createState() => _AppleIosDestinationSearchState();
}

class _AppleIosDestinationSearchState extends State<AppleIosDestinationSearch> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<String> _suggestions = [];

  // Core DIU Hubs
  static const List<String> _commonHubs = [
    'Uttara Sector 11 (House Building)',
    'Uttara North Metro Station (Diabari)',
    'Uttara Sector 3 (Rajlakshmi)',
    'Uttara Azampur Bus Stand',
    'Mirpur 10 Roundabout',
    'Mirpur 12 Metro Station',
    'Mirpur 1 Bus Stand',
    'Dhanmondi 32 (Metro Station)',
    'Dhanmondi 27 / Rapa Plaza',
    'Birulia Bridge Stand',
    'Savar City Centre',
    'Gazipur Chowrasta',
    'ECB Chattar (Airport Road)',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentQuery);
    _updateSuggestions(widget.currentQuery);
  }

  @override
  void didUpdateWidget(covariant AppleIosDestinationSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentQuery != _controller.text) {
      _controller.text = widget.currentQuery;
      _updateSuggestions(widget.currentQuery);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateSuggestions(String text) {
    final query = text.trim().toLowerCase();
    final Set<String> pooled = {};

    // Pool from active rides
    for (final r in widget.allRides) {
      if (r.destinationName.isNotEmpty) pooled.add(r.destinationName);
      if (r.destinationSubtitle != null && r.destinationSubtitle!.isNotEmpty) {
        pooled.add(r.destinationSubtitle!);
      }
    }
    // Add common hubs
    pooled.addAll(_commonHubs);

    if (query.isEmpty) {
      // Suggest top 4 common hubs
      setState(() {
        _suggestions = _commonHubs.take(4).toList();
      });
    } else {
      // Filter dynamically
      final matches = pooled
          .where((place) => place.toLowerCase().contains(query))
          .take(6)
          .toList();

      // If no exact substring in pooled, still include query
      if (matches.isEmpty && query.length >= 2) {
        matches.add(text.trim());
      }

      setState(() {
        _suggestions = matches;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3D Apple-Style Floating Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: hasText ? const Color(0xFF007AFF) : Colors.black.withOpacity(0.08),
                width: hasText ? 1.8 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasText
                      ? const Color(0xFF007AFF).withOpacity(0.18)
                      : Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                const BoxShadow(
                  color: Colors.white,
                  blurRadius: 1,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              children: [
                // 3D Search Icon
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF007AFF), Color(0xFF0051B3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF007AFF).withOpacity(0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.search, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),

                // Text Input
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: AppTypography.bodyLgMedium.copyWith(
                      color: const Color(0xFF1C1C1E),
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Where to? (e.g. Uttara, Mirpur 10)...',
                      hintStyle: AppTypography.bodyMd.copyWith(
                        color: const Color(0xFF8E8E93),
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (val) {
                      _updateSuggestions(val);
                      widget.onQueryChanged(val);
                    },
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        widget.onDestinationSelected(val.trim());
                      }
                    },
                  ),
                ),

                // Clear or Status button
                if (hasText)
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Color(0xFF8E8E93), size: 20),
                    onPressed: () {
                      _controller.clear();
                      _updateSuggestions('');
                      widget.onClear();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.two_wheeler, size: 14, color: Color(0xFF007AFF)),
                        SizedBox(width: 4),
                        Text(
                          'Moto',
                          style: TextStyle(
                            color: Color(0xFF007AFF),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Auto-Suggestions (Apple iOS 3D Chips / Pills)
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 13, color: Color(0xFF007AFF)),
                const SizedBox(width: 5),
                Text(
                  hasText ? 'Suggested destination matches:' : 'Popular DIU commute hubs:',
                  style: AppTypography.labelSm.copyWith(
                    color: const Color(0xFF8E8E93),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  final isSelected = hasText &&
                      item.toLowerCase().contains(_controller.text.trim().toLowerCase());

                  return InkWell(
                    onTap: () {
                      _controller.text = item;
                      _updateSuggestions(item);
                      widget.onDestinationSelected(item);
                      _focusNode.unfocus();
                    },
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF007AFF) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF007AFF)
                              : Colors.black.withOpacity(0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isSelected
                                ? const Color(0xFF007AFF).withOpacity(0.3)
                                : Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 13,
                            color: isSelected ? Colors.white : const Color(0xFF007AFF),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            item,
                            style: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
