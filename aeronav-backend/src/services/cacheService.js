const Redis = require('ioredis');
const NodeCache = require('node-cache');
const dotenv = require('dotenv');

dotenv.config();

class CacheService {
  constructor() {
    this.memoryCache = new NodeCache({ stdTTL: 1800, checkperiod: 120 });
    this.useRedis = false;
    
    if (process.env.REDIS_URL) {
      this.redis = new Redis(process.env.REDIS_URL, {
        retryStrategy: (times) => {
          if (times > 3) {
            console.log('Redis connection failed, falling back to memory cache.');
            this.useRedis = false;
            return null; // Stop retrying
          }
          return Math.min(times * 50, 2000);
        }
      });
      
      this.redis.on('connect', () => {
        console.log('Redis connected successfully.');
        this.useRedis = true;
      });
      
      this.redis.on('error', (err) => {
        console.warn('Redis error:', err.message);
      });
    } else {
      console.log('No REDIS_URL provided, using in-memory cache only.');
    }
  }

  async get(key) {
    if (this.useRedis) {
      try {
        const val = await this.redis.get(key);
        return val ? JSON.parse(val) : null;
      } catch (err) {
        console.warn('Redis GET failed:', err.message);
      }
    }
    return this.memoryCache.get(key);
  }

  async set(key, value, ttlSeconds = 1800) {
    if (this.useRedis) {
      try {
        await this.redis.set(key, JSON.stringify(value), 'EX', ttlSeconds);
        return;
      } catch (err) {
        console.warn('Redis SET failed:', err.message);
      }
    }
    this.memoryCache.set(key, value, ttlSeconds);
  }
}

module.exports = new CacheService();
