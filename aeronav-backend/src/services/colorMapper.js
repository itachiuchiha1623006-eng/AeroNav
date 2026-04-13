const CPCB_TIERS = [
  { min: 0, max: 50, category: 'Good', color: '#00E400' },
  { min: 51, max: 100, category: 'Satisfactory', color: '#92D14F' },
  { min: 101, max: 200, category: 'Moderate', color: '#FFFF00' },
  { min: 201, max: 300, category: 'Poor', color: '#FF7E00' },
  { min: 301, max: 400, category: 'Very Poor', color: '#FF0000' },
  { min: 401, max: 5000, category: 'Severe', color: '#7E0023' } // Max arbitrary high number
];

function getCategoryAndColor(aqi) {
  // Handle invalid/missing
  if (aqi === null || aqi === undefined || isNaN(aqi)) {
    return { category: 'Unknown', color: '#808080' };
  }
  
  const val = Math.round(Math.max(0, aqi)); // Prevent negatives, round
  
  for (const tier of CPCB_TIERS) {
    if (val >= tier.min && val <= tier.max) {
      return { category: tier.category, color: tier.color };
    }
  }
  
  // Anything > 500 falls here
  return { category: 'Severe', color: '#7E0023' };
}

module.exports = {
  getCategoryAndColor,
  CPCB_TIERS
};
