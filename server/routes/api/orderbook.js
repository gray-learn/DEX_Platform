const express = require('express');
const router = express.Router();

// Mock data for order book with more realistic ETH/USDT data
const generateMockOrders = (side, basePrice, count = 15) => {
  const orders = [];
  
  for (let i = 0; i < count; i++) {
    let priceVariation, amount;
    
    if (side === 'buy') {
      // Buy orders: decreasing prices from base price
      priceVariation = -i * (Math.random() * 2 + 0.5); // More realistic price gaps
      amount = Math.random() * 50 + 0.1; // Larger amounts for buy orders
    } else {
      // Sell orders: increasing prices from base price
      priceVariation = i * (Math.random() * 2 + 0.5);
      amount = Math.random() * 30 + 0.05; // Varied amounts for sell orders
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
  },
  'BNB/USDT': { 
    basePrice: 315, 
    lastPrice: 314.80, 
    change24h: -0.42,
    volume24h: 89540.32,
    high24h: 318.45,
    low24h: 312.18
  },
  'ADA/USDT': { 
    basePrice: 0.58, 
    lastPrice: 0.5825, 
    change24h: 3.21,
    volume24h: 2540000.67,
    high24h: 0.5890,
    low24h: 0.5610
  }
};

// @route   GET api/orderbook/* (handles ETH/USDT format)
// @desc    Get order book for trading pair
// @access  Public
router.get('/*', (req, res) => {
  try {
    const pair = req.params[0] || req.params.pair; // Handle both formats
    const pairData = tradingPairs[pair.toUpperCase()];
    
    if (!pairData) {
      return res.status(404).json({ message: 'Trading pair not found' });
    }

    // Add some randomness to base price for more realistic data
    const priceVolatility = pair.toUpperCase() === 'ETH/USDT' ? 15 : 10;
    const currentBasePrice = pairData.basePrice + (Math.random() - 0.5) * priceVolatility;
    
    // Generate more orders for better depth
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
      // Add spread calculation
      spread: sellOrders.length > 0 && buyOrders.length > 0 ? 
        (parseFloat(sellOrders[0].price) - parseFloat(buyOrders[0].price)).toFixed(2) : '0.00'
    };

    res.json(orderBook);
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

// @route   GET api/orderbook/pairs/all
// @desc    Get all available trading pairs
// @access  Public
router.get('/pairs/all', (req, res) => {
  try {
    const pairs = Object.keys(tradingPairs).map(pair => ({
      pair,
      lastPrice: tradingPairs[pair].lastPrice,
      change24h: tradingPairs[pair].change24h
    }));

    res.json(pairs);
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

// @route   GET api/orderbook/trades/:pair
// @desc    Get recent trades for trading pair
// @access  Public
router.get('/trades/:pair', (req, res) => {
  try {
    const { pair } = req.params;
    const pairData = tradingPairs[pair.toUpperCase()];
    
    if (!pairData) {
      return res.status(404).json({ message: 'Trading pair not found' });
    }

    // Generate mock recent trades
    const trades = [];
    for (let i = 0; i < 20; i++) {
      const side = Math.random() > 0.5 ? 'buy' : 'sell';
      const price = pairData.basePrice + (Math.random() - 0.5) * 20;
      const amount = Math.random() * 5 + 0.01;
      const timestamp = new Date(Date.now() - i * 30000).toISOString();
      
      trades.push({
        id: `trade-${i + 1}`,
        price: price.toFixed(2),
        amount: amount.toFixed(4),
        side,
        timestamp
      });
    }

    res.json({ pair: pair.toUpperCase(), trades });
  } catch (err) {
    console.error(err.message);
    res.status(500).send('Server Error');
  }
});

module.exports = router;