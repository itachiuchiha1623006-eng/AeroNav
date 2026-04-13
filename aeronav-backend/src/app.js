const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

const navigationRoutes = require('./routes/navigation');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Basic health check
app.get('/health', (req, res) => {
  res.json({ status: 'AeroNav Backend is running', timestamp: new Date() });
});

// API Routes
app.use('/api', navigationRoutes);

app.listen(PORT, () => {
  console.log(`Server is listening on port ${PORT}`);
});
