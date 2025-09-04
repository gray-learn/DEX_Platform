const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "http://localhost:3000",
    methods: ["GET", "POST"]
  }
});

// Connect Database
// connectDB();

// Init Middleware
app.use(cors());
app.use(express.json());

// Define Routes
app.use('/api/users', require('./server/routes/api/users'));
app.use('/api/auth', require('./server/routes/api/auth'));
app.use('/api/profile', require('./server/routes/api/profile'));
app.use('/api/posts', require('./server/routes/api/posts'));
app.use('/api/orderbook', require('./server/routes/api/orderbook'));

// Serve static assets in production
if (process.env.NODE_ENV === 'production') {
  // Set static folder
  app.use(express.static('client/build'));

  app.get('*', (req, res) => {
    res.sendFile(path.resolve(__dirname, 'client', 'build', 'index.html'));
  });
}

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);
  
  socket.on('join_orderbook', (pair) => {
    socket.join(`orderbook_${pair}`);
    console.log(`Client ${socket.id} joined orderbook for ${pair}`);
  });
  
  socket.on('leave_orderbook', (pair) => {
    socket.leave(`orderbook_${pair}`);
    console.log(`Client ${socket.id} left orderbook for ${pair}`);
  });
  
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Mock order book updates every 2 seconds
const broadcastOrderBookUpdates = () => {
  const pairs = ['ETH/USDT', 'BTC/USDT', 'BNB/USDT', 'ADA/USDT'];
  const tradingPairs = {
    'ETH/USDT': { basePrice: 2450, lastPrice: 2450.50, change24h: 2.34 },
    'BTC/USDT': { basePrice: 43500, lastPrice: 43520.30, change24h: 1.87 },
    'BNB/USDT': { basePrice: 315, lastPrice: 314.80, change24h: -0.42 },
    'ADA/USDT': { basePrice: 0.58, lastPrice: 0.5825, change24h: 3.21 }
  };

  pairs.forEach(pair => {
    const pairData = tradingPairs[pair];
    const currentBasePrice = pairData.basePrice + (Math.random() - 0.5) * 20;
    
    // Generate small price updates
    const newPrice = pairData.lastPrice + (Math.random() - 0.5) * 5;
    tradingPairs[pair].lastPrice = Math.max(0.01, newPrice);
    
    const update = {
      pair,
      lastPrice: tradingPairs[pair].lastPrice.toFixed(pair.includes('USDT') && !pair.includes('BTC') ? 4 : 2),
      change24h: pairData.change24h,
      timestamp: new Date().toISOString(),
      // Send a few updated orders
      bids: Array.from({length: 3}, (_, i) => ({
        price: (currentBasePrice - i * 0.5).toFixed(2),
        amount: (Math.random() * 10 + 0.1).toFixed(4),
        total: ((currentBasePrice - i * 0.5) * (Math.random() * 10 + 0.1)).toFixed(4)
      })),
      asks: Array.from({length: 3}, (_, i) => ({
        price: (currentBasePrice + i * 0.5).toFixed(2),
        amount: (Math.random() * 10 + 0.1).toFixed(4),
        total: ((currentBasePrice + i * 0.5) * (Math.random() * 10 + 0.1)).toFixed(4)
      }))
    };
    
    io.to(`orderbook_${pair}`).emit('orderbook_update', update);
  });
};

// Start broadcasting updates
setInterval(broadcastOrderBookUpdates, 2000);

const PORT = process.env.PORT || 5025;

server.listen(PORT, () => {
  console.log(`Server started on port ${PORT}`);
  console.log('Socket.IO server ready for real-time order book updates');
});
