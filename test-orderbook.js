const axios = require('axios');

// Test the orderbook API specifically for ETH/USDT
async function testOrderBookAPI() {
  const BASE_URL = 'http://localhost:5025';
  
  try {
    console.log('🔍 Testing ETH/USDT Order Book API...\n');
    
    // Test ETH/USDT order book
    const response = await axios.get(`${BASE_URL}/api/orderbook/ETH/USDT`);
    const orderBook = response.data;
    
    console.log('📊 ETH/USDT Order Book Data:');
    console.log('================================');
    console.log(`Pair: ${orderBook.pair}`);
    console.log(`Last Price: $${orderBook.lastPrice}`);
    console.log(`24h Change: ${orderBook.change24h}%`);
    console.log(`24h Volume: ${orderBook.volume24h} ETH`);
    console.log(`24h High: $${orderBook.high24h}`);
    console.log(`24h Low: $${orderBook.low24h}`);
    console.log(`Spread: $${orderBook.spread}`);
    console.log(`Timestamp: ${orderBook.timestamp}`);
    
    console.log('\n🟢 Top 5 Buy Orders (Bids):');
    console.log('Price ($)  | Amount (ETH) | Total ($)');
    console.log('--------------------------------------');
    orderBook.bids.slice(0, 5).forEach(bid => {
      console.log(`${bid.price.padEnd(10)} | ${bid.amount.padEnd(12)} | ${bid.total}`);
    });
    
    console.log('\n🔴 Top 5 Sell Orders (Asks):');
    console.log('Price ($)  | Amount (ETH) | Total ($)');
    console.log('--------------------------------------');
    orderBook.asks.slice(0, 5).forEach(ask => {
      console.log(`${ask.price.padEnd(10)} | ${ask.amount.padEnd(12)} | ${ask.total}`);
    });
    
    console.log('\n✅ API Test Successful!');
    
  } catch (error) {
    console.error('❌ API Test Failed:', error.message);
    if (error.code === 'ECONNREFUSED') {
      console.log('💡 Make sure the server is running on port 5025');
    }
  }
}

// Run the test
testOrderBookAPI();