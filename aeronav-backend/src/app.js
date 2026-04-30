const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pinoHttp = require('pino-http');
const pino = require('pino');

dotenv.config();

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const navigationRoutes = require('./routes/navigation');
const aqiRoutes = require('./routes/aqi');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(pinoHttp({ logger }));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api/', limiter);

// Basic health check v2
app.get('/health', (req, res) => {
  res.json({
    status: 'AeroNav Backend is running',
    uptime: process.uptime(),
    timestamp: new Date()
  });
});

// API Routes
app.use('/api/navigation', navigationRoutes);
app.use('/api/aqi', aqiRoutes);


app.use((err, req, res, next) => {
  logger.error(err.stack);
  res.status(500).json({ error: 'Internal Server Error', details: err.message });
});

app.listen(PORT, '0.0.0.0', () => {
  logger.info(`Server is listening on 0.0.0.0:${PORT}`);
});
