const { haversineDistance } = require('./geoUtils');

function calculateIDW(targetPoint, stations, p = 2, maxDistance = 50) {
  let numerator = 0;
  let denominator = 0;
  let validStationsFound = false;

  for (const station of stations) {
    const dist = haversineDistance(targetPoint, { lat: station.lat, lng: station.lng });

    // If exactly on station (distance 0), return station's value immediately
    if (dist < 0.1) {
      return station.value;
    }

    if (dist <= maxDistance) {
      const weight = 1 / Math.pow(dist, p);
      numerator += weight * station.value;
      denominator += weight;
      validStationsFound = true;
    }
  }

  if (!validStationsFound || denominator === 0) {
    return null; // Return null if no stations within maxDistance
  }

  return numerator / denominator;
}

module.exports = {
  calculateIDW
};
