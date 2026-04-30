import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../services/geocoding_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GeocodingService _geocodingService = GeocodingService();
  
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _geocodingService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAFA),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          "Destination", 
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[300]!)
            ),

          )
        ],
      ),
      body: Column(
        children: [
          // Destination Input Card
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))
              ]
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Left side connection graphics
                  SizedBox(
                    width: 50,
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Container(
                          width: 8, 
                          height: 8, 
                          decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle)
                        ),
                        Expanded(
                          child: Container(
                            width: 1, 
                            color: Colors.grey[300],
                            margin: const EdgeInsets.symmetric(vertical: 4),
                          )
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 8),
                            Container(
                              width: 8, 
                              height: 8, 
                              decoration: const BoxDecoration(color: Color(0xFFE57373), shape: BoxShape.circle)
                            ),
                            const Icon(Icons.arrow_right, color: Color(0xFFE57373), size: 16),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  
                  // Right side input fields
                  Expanded(
                    child: Column(
                      children: [
                        // From location (read-only for now)
                        Container(
                          height: 56,
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.grey[200]!))
                          ),
                          child: const Text(
                            "Your current location", 
                            style: TextStyle(color: Colors.black87, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        
                        // Destination input
                        SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                   controller: _searchController,
                                   autofocus: true,
                                   onChanged: _onSearchChanged,
                                   style: const TextStyle(fontSize: 15),
                                   decoration: const InputDecoration(
                                     hintText: "Enter destination",
                                     hintStyle: TextStyle(color: Colors.grey),
                                     border: InputBorder.none,
                                   )
                                ),
                              ),
                              Container(
                                width: 1, 
                                height: 30, 
                                color: Colors.grey[200]
                              ),
                              
                            ],
                          )
                        )
                      ],
                    ),
                  )
                ],
              ),
            )
          ),

          // Loading Indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF2DB87A)),
              ),
            ),
            
          // Results List
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, index) {
                final place = _results[index];
                final nameStr = place['name'] as String;
                final parts = nameStr.split(', ');
                final primaryText = parts.isNotEmpty ? parts.first : nameStr;
                final secondaryText = parts.length > 1 ? parts.skip(1).join(', ') : '';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: const Icon(Icons.history, color: Colors.grey),
                  title: Text(
                    primaryText,
                    style: const TextStyle(fontWeight: FontWeight.w400, color: Colors.black87, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: secondaryText.isNotEmpty 
                    ? Text(
                        secondaryText,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                  onTap: () {
                    context.pop({
                      'name': place['name'],
                      'latitude': place['latitude'],
                      'longitude': place['longitude'],
                    });
                  },
                );
              },
            ),
          ),
          
          // Bottom Locate on Map Button
          GestureDetector(
            onTap: () {
              context.pop({'action': 'pick_on_map'});
            },
            child: Container(
              padding: EdgeInsets.only(
                top: 16, 
                bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 16
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on, color: Colors.black87, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Locate on Map", 
                    style: TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)
                  )
                ],
              )
            ),
          )
        ],
      ),
    );
  }
}
