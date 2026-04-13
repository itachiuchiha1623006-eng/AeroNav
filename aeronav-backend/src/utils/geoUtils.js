// Haversine distance between two coordinates in km
function haversineDistance(coords1, coords2) {
  function toRad(x) {
    return x * Math.PI / 180;
  }

  const lon1 = coords1.lng;
  const lat1 = coords1.lat;
  const lon2 = coords2.lng;
  const lat2 = coords2.lat;

  const R = 6371; // Earth radius in km
  const x1 = lat2 - lat1;
  const dLat = toRad(x1);
  const x2 = lon2 - lon1;
  const dLon = toRad(x2);

  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// Split a GeoJSON LineString path into segments of approximately targetLengthKm
function splitRouteIntoSegments(coordinates, targetLengthKm = 1.0) {
  const segments = [];
  if (!coordinates || coordinates.length < 2) return segments;

  let currentSegment = {
    id: 1,
    startPoint: { lng: coordinates[0][0], lat: coordinates[0][1] },
    endPoint: null,
    distanceKm: 0,
    coordinates: [coordinates[0]] // Store coords to rebuild geometry if needed
  };

  let accumulatedDist = 0;

  for (let i = 0; i < coordinates.length - 1; i++) {
    const p1 = { lng: coordinates[i][0], lat: coordinates[i][1] };
    const p2 = { lng: coordinates[i + 1][0], lat: coordinates[i + 1][1] };
    const dist = haversineDistance(p1, p2);

    accumulatedDist += dist;
    currentSegment.distanceKm += dist;
    currentSegment.coordinates.push(coordinates[i + 1]);

    // If segment reaches target length or it's the last coordinate
    if (accumulatedDist >= targetLengthKm || i === coordinates.length - 2) {
      currentSegment.endPoint = p2;
      
      // Calculate midpoint for AQI logic (simplification: simple average of start and end)
      currentSegment.midpoint = {
        lat: (currentSegment.startPoint.lat + currentSegment.endPoint.lat) / 2,
        lng: (currentSegment.startPoint.lng + currentSegment.endPoint.lng) / 2
      };

      segments.push(currentSegment);

      // Start new segment
      if (i < coordinates.length - 2) {
        currentSegment = {
          id: segments.length + 1,
          startPoint: p2,
          endPoint: null,
          distanceKm: 0,
          coordinates: [coordinates[i + 1]]
        };
        accumulatedDist = 0;
      }
    }
  }

  return segments;
}

module.exports = {
  haversineDistance,
  splitRouteIntoSegments
};
