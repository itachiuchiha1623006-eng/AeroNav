// Samples N evenly-spaced points along a GeoJSON LineString (array of [lng, lat])
// Using Haversine formula to find total distance, and sample along that distance
function getDistanceFromLatLonInKm(lat1, lon1, lat2, lon2) {
  var R = 6371; // Radius of the earth in km
  var dLat = deg2rad(lat2 - lat1);
  var dLon = deg2rad(lon2 - lon1);
  var a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  var d = R * c; // Distance in km
  return d;
}

function deg2rad(deg) {
  return deg * (Math.PI / 180);
}

function interpolatePoint(p1, p2, fraction) {
  return [
    p1[0] + fraction * (p2[0] - p1[0]),
    p1[1] + fraction * (p2[1] - p1[1])
  ];
}

function sampleRoutePoints(geojsonCoords, numSamples = 5) {
  if (!geojsonCoords || geojsonCoords.length === 0) return [];
  if (geojsonCoords.length <= numSamples || numSamples <= 1) {
    return geojsonCoords.map(coord => ({ lat: coord[1], lng: coord[0] })).slice(0, numSamples);
  }

  // Calculate total distance and distances between segments
  const segments = [];
  let totalDist = 0;
  for (let i = 0; i < geojsonCoords.length - 1; i++) {
    const p1 = geojsonCoords[i];
    const p2 = geojsonCoords[i+1];
    const dist = getDistanceFromLatLonInKm(p1[1], p1[0], p2[1], p2[0]);
    segments.push({ p1, p2, dist, cumDist: totalDist + dist });
    totalDist += dist;
  }

  if (totalDist === 0) {
      return [{ lat: geojsonCoords[0][1], lng: geojsonCoords[0][0] }];
  }

  const sampledCoords = [];
  // We want to sample at: 0, 1/(N-1), 2/(N-1), ..., 1 times totalDist
  for (let i = 0; i < numSamples; i++) {
    const targetDist = (i / (numSamples - 1)) * totalDist;
    if (i === 0) {
      sampledCoords.push(geojsonCoords[0]);
    } else if (i === numSamples - 1) {
      sampledCoords.push(geojsonCoords[geojsonCoords.length - 1]);
    } else {
      // Find the segment that contains targetDist
      for (let j = 0; j < segments.length; j++) {
        const seg = segments[j];
        if (targetDist <= seg.cumDist) {
          const segStartDist = seg.cumDist - seg.dist;
          const distInSeg = targetDist - segStartDist;
          const fraction = seg.dist === 0 ? 0 : distInSeg / seg.dist;
          sampledCoords.push(interpolatePoint(seg.p1, seg.p2, fraction));
          break;
        }
      }
    }
  }

  return sampledCoords.map(coord => ({ lat: coord[1], lng: coord[0] }));
}

module.exports = {
  sampleRoutePoints,
  getDistanceFromLatLonInKm
};
