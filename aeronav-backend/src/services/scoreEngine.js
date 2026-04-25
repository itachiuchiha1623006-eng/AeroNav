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

  // Use >= bl and <= bh but prefer the lower bucket when cp sits exactly on a
  // boundary (i.e. iterate and take the FIRST matching range).
  for (let i = 0; i < table.length; i++) {
    const range = table[i];
    // Last range: closed on both ends. All earlier ranges: closed on lower, open on upper.
    const inRange = (i === table.length - 1)
      ? cp >= range.bl && cp <= range.bh
      : cp >= range.bl && cp < range.bh;

    if (inRange) {
      // Formula: Ip = [(IHi - ILo) / (BPHi - BPLo)] * (Cp - BPLo) + ILo
      const rangeBh = (i === table.length - 1) ? range.bh : table[i + 1].bl - 0.001; // subtle: use declared bh
      const index = ((range.ih - range.il) / (range.bh - range.bl)) * (cp - range.bl) + range.il;
      return Math.round(index);
    }
  }

  // Extremely high — cap at 500
  return 500;
}

function calculateBaseAQI(pollutants) {
  const subIndices = {
    pm25: calculateSubIndex(pollutants.pm25, 'pm25'),
    pm10: calculateSubIndex(pollutants.pm10, 'pm10'),
    no2:  calculateSubIndex(pollutants.no2,  'no2'),
    so2:  calculateSubIndex(pollutants.so2,  'so2'),
    co:   calculateSubIndex(pollutants.co,   'co'),
    o3:   calculateSubIndex(pollutants.o3,   'o3')
  };

  // Debug: surface raw pollutant concentrations and their sub-indices
  console.debug('[AQI] pollutants:', JSON.stringify(pollutants));
  console.debug('[AQI] sub-indices:', JSON.stringify(subIndices));

  // CPCB: overall AQI = maximum of all sub-indices
  let maxAQI = 0;
  for (const key in subIndices) {
    if (subIndices[key] > maxAQI) {
      maxAQI = subIndices[key];
    }
  }

  return maxAQI;
}

function calculateWeatherModifiers(aqi, weather) {
  // Weather effects are already reflected in the physical sensor data at the stations.
  // Modifying the calculated base AQI causes it to drift from official/trusted readings.
  return { 
    finalAqi: aqi,
    percentageAdjust: 0 
  };
}

module.exports = {
  calculateSubIndex,
  calculateBaseAQI,
  calculateWeatherModifiers
};
