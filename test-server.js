const express = require('express');
const cors = require('cors');

const app = express();

// Init Middleware
app.use(cors());
app.use(express.json());

// Mock data for order book with realistic ETH/USDT data
const generateMockOrders = (side, basePrice, count = 15) => {
  const orders = [];
  
  for (let i = 0; i < count; i++) {
    let priceVariation, amount;
    
    if (side === 'buy') {
      // Buy orders: decreasing prices from base price
      priceVariation = -i * (Math.random() * 2 + 0.5);
      amount = Math.random() * 50 + 0.1;
    } else {
      // Sell orders: increasing prices from base price
      priceVariation = i * (Math.random() * 2 + 0.5);
      amount = Math.random() * 30 + 0.05;
    }
    
    const price = Math.max(0.01, basePrice + priceVariation);
    const total = price * amount;
    
    orders.push({
      id: `${side}-${i + 1}`,
      price: price.toFixed(2),
      amount: amount.toFixed(4),
      total: total.toFixed(2),
      side
    });
  }
  return orders;
};

const tradingPairs = {
  'ETH/USDT': { 
    basePrice: 2450, 
    lastPrice: 2450.50, 
    change24h: 2.34,
    volume24h: 125000.45,
    high24h: 2478.20,
    low24h: 2389.10
  },
  'BTC/USDT': { 
    basePrice: 43500, 
    lastPrice: 43520.30, 
    change24h: 1.87,
    volume24h: 15420.87,
    high24h: 44120.50,
    low24h: 42890.25
  }
};

// ETH/USDT Order Book endpoint - handle URL encoded slashes
app.get('/api/orderbook/*', (req, res) => {
  try {
    const pair = req.params[0]; // Get everything after /api/orderbook/
    const pairData = tradingPairs[pair.toUpperCase()];
    
    if (!pairData) {
      return res.status(404).json({ message: 'Trading pair not found' });
    }

    // Add some randomness for ETH/USDT
    const priceVolatility = pair.toUpperCase() === 'ETH/USDT' ? 15 : 10;
    const currentBasePrice = pairData.basePrice + (Math.random() - 0.5) * priceVolatility;
    
    // Generate realistic orders
    const buyOrders = generateMockOrders('buy', currentBasePrice, 20);
    const sellOrders = generateMockOrders('sell', currentBasePrice, 20);

    const orderBook = {
      pair: pair.toUpperCase(),
      lastPrice: pairData.lastPrice,
      change24h: pairData.change24h,
      volume24h: pairData.volume24h,
      high24h: pairData.high24h,
      low24h: pairData.low24h,
      timestamp: new Date().toISOString(),
      bids: buyOrders.sort((a, b) => parseFloat(b.price) - parseFloat(a.price)),
      asks: sellOrders.sort((a, b) => parseFloat(a.price) - parseFloat(b.price)),
      spread: sellOrders.length > 0 && buyOrders.length > 0 ? 
        (parseFloat(sellOrders[0].price) - parseFloat(buyOrders[0].price)).toFixed(2) : '0.00'
    };

    res.json(orderBook);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: 'Server Error' });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'OK', message: 'Order Book API is running' });
});

const PORT = 5025;

app.listen(PORT, () => {
  console.log(`🚀 Order Book Test Server started on port ${PORT}`);
  console.log(`📊 ETH/USDT endpoint: http://localhost:${PORT}/api/orderbook/ETH/USDT`);
  console.log(`❤️  Health check: http://localhost:${PORT}/health`);
});