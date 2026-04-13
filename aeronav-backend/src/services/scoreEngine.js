// CPCB Breakpoints (simplified standard values for demonstration, 24 hr ave for particulate, 8 hr for gases)
// BPLo, BPHi, ILo, IHi
const BREAKPOINTS = {
  pm25: [
    { bl: 0, bh: 30, il: 0, ih: 50 },
    { bl: 31, bh: 60, il: 51, ih: 100 },
    { bl: 61, bh: 90, il: 101, ih: 200 },
    { bl: 91, bh: 120, il: 201, ih: 300 },
    { bl: 121, bh: 250, il: 301, ih: 400 },
    { bl: 251, bh: 1000, il: 401, ih: 500 }
  ],
  pm10: [
    { bl: 0, bh: 50, il: 0, ih: 50 },
    { bl: 51, bh: 100, il: 51, ih: 100 },
    { bl: 101, bh: 250, il: 101, ih: 200 },
    { bl: 251, bh: 350, il: 201, ih: 300 },
    { bl: 351, bh: 430, il: 301, ih: 400 },
    { bl: 431, bh: 1000, il: 401, ih: 500 }
  ],
  no2: [
    { bl: 0, bh: 40, il: 0, ih: 50 },
    { bl: 41, bh: 80, il: 51, ih: 100 },
    { bl: 81, bh: 180, il: 101, ih: 200 },
    { bl: 181, bh: 280, il: 201, ih: 300 },
    { bl: 281, bh: 400, il: 301, ih: 400 },
    { bl: 401, bh: 1000, il: 401, ih: 500 }
  ],
  so2: [
    { bl: 0, bh: 40, il: 0, ih: 50 },
    { bl: 41, bh: 80, il: 51, ih: 100 },
    { bl: 81, bh: 380, il: 101, ih: 200 },
    { bl: 381, bh: 800, il: 201, ih: 300 },
    { bl: 801, bh: 1600, il: 301, ih: 400 },
    { bl: 1601, bh: 10000, il: 401, ih: 500 }
  ],
  co: [
    { bl: 0, bh: 1.0, il: 0, ih: 50 },
    { bl: 1.1, bh: 2.0, il: 51, ih: 100 },
    { bl: 2.1, bh: 10, il: 101, ih: 200 },
    { bl: 10.1, bh: 17, il: 201, ih: 300 },
    { bl: 17.1, bh: 34, il: 301, ih: 400 },
    { bl: 34.1, bh: 100, il: 401, ih: 500 }
  ],
  o3: [
    { bl: 0, bh: 50, il: 0, ih: 50 },
    { bl: 51, bh: 100, il: 51, ih: 100 },
    { bl: 101, bh: 168, il: 101, ih: 200 },
    { bl: 169, bh: 208, il: 201, ih: 300 },
    { bl: 209, bh: 748, il: 301, ih: 400 },
    { bl: 749, bh: 1000, il: 401, ih: 500 } // using 1hr avg for high O3 limits approximation
  ]
};

function calculateSubIndex(cp, pollutantType) {
  if (cp === null || cp === undefined || isNaN(cp)) return 0;
  
  const table = BREAKPOINTS[pollutantType];
  if (!table) return 0;

  for (const range of table) {
    if (cp >= range.bl && cp <= range.bh) {
      // Formula: Ip = [(IHi - ILo) / (BPHi - BPLo)] * (Cp - BPLo) + ILo
      const index = ((range.ih - range.il) / (range.bh - range.bl)) * (cp - range.bl) + range.il;
      return Math.round(index);
    }
  }
  
  // If extremely high
  const highestLimit = table[table.length - 1];
  const index = Math.round(((500 - 401) / (highestLimit.bh - highestLimit.bl)) * (cp - highestLimit.bl) + 401);
  return Math.min(Math.max(index, 500), 500); // cap at 500 typically, but real world might be higher
}

function calculateBaseAQI(pollutants) {
  const subIndices = {
    pm25: calculateSubIndex(pollutants.pm25, 'pm25'),
    pm10: calculateSubIndex(pollutants.pm10, 'pm10'),
    no2: calculateSubIndex(pollutants.no2, 'no2'),
    so2: calculateSubIndex(pollutants.so2, 'so2'),
    co: calculateSubIndex(pollutants.co, 'co'),
    o3: calculateSubIndex(pollutants.o3, 'o3')
  };

  // Max sub-index
  let maxAQI = 0;
  for (const key in subIndices) {
    if (subIndices[key] > maxAQI) {
      maxAQI = subIndices[key];
    }
  }

  // To be legally CPCB compliant, we need at least one particulate matter (PM2.5 or PM10) 
  // and one of the other parameters. For this MVP, we proceed if we have any valid data.
  
  return maxAQI;
}

function calculateWeatherModifiers(aqi, weather) {
  if (!weather || aqi <= 0) return { finalAqi: aqi, percentageAdjust: 0 };
  
  let tempAqi = aqi;
  let adjustPercentage = 0; // Negative means cleaner

  // Wind logic
  if (weather.windSpeed > 20) { // km/h
    adjustPercentage -= 10;
  } else if (weather.windSpeed < 5) {
    adjustPercentage += 15;
  }

  // Rain logic (washout)
  if (weather.rainfall > 7.5) {
    adjustPercentage -= 35;
  } else if (weather.rainfall > 2.5) {
    adjustPercentage -= 20;
  }

  // Humidity (hygroscopic growth for particulates)
  if (weather.humidity > 85) {
    adjustPercentage += 5;
  }

  // Apply adjusting percentage
  tempAqi = tempAqi * (1 + (adjustPercentage / 100.0));
  
  return { 
    finalAqi: Math.round(Math.min(tempAqi, 500)), // cap to max 500
    percentageAdjust: adjustPercentage 
  };
}

module.exports = {
  calculateSubIndex,
  calculateBaseAQI,
  calculateWeatherModifiers
};
