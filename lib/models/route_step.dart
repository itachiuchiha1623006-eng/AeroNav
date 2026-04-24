import 'package:latlong2/latlong.dart';

class RouteStep {
  final LatLng point;
  final double distance;
  final double duration;
  final String instruction;
  final String maneuverType;
  final String modifier;
  final String name;

  RouteStep({
    required this.point,
    required this.distance,
    required this.duration,
    required this.instruction,
    required this.maneuverType,
    required this.modifier,
    required this.name,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>? ?? {};
    final location = maneuver['location'] as List<dynamic>? ?? [0.0, 0.0];
    
    // OSRM returns coordinates as [longitude, latitude]
    final latLng = LatLng(location[1].toDouble(), location[0].toDouble());
    
    // Simple instruction generator for fallback
    final type = maneuver['type'] as String? ?? '';
    final mod = maneuver['modifier'] as String? ?? '';
    final streetName = json['name'] as String? ?? '';
    
    String derivedInstruction = '';
    if (type == 'turn') {
      derivedInstruction = 'Turn $mod on $streetName';
    } else if (type == 'new name') {
      derivedInstruction = 'Continue on $streetName';
    } else if (type == 'depart') {
      derivedInstruction = 'Head $mod on $streetName';
    } else if (type == 'arrive') {
      derivedInstruction = 'You have reached your destination';
    } else if (type == 'roundabout') {
      derivedInstruction = 'Enter roundabout and take the route on $streetName';
    } else {
      derivedInstruction = 'Proceed on $streetName';
    }

    if (derivedInstruction.endsWith('on ')) {
      derivedInstruction = derivedInstruction.replaceAll('on ', '');
    }

    return RouteStep(
      point: latLng,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      instruction: derivedInstruction,
      maneuverType: type,
      modifier: mod,
      name: streetName,
    );
  }
}
