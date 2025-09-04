const axios = require('axios');

// Simulate the orderBookService.getOrderBook function for ETH/USDT
class OrderBookService {
  constructor() {
    this.BASE_URL = 'http://localhost:5025';
  }

  async getOrderBook(pair) {
    try {
      console.log(`📡 Fetching order book for ${pair}...`);
      const response = await axios.get(`${this.BASE_URL}/api/orderbook/${pair}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching order book:', error.message);
      throw error;
    }
  }
}

// Demo the service
async function demoOrderBookService() {
  const orderBookService = new OrderBookService();
  
  try {
    // This is exactly how the line 84-91 in orderBookService.ts works
    console.log('🚀 Demo: OrderBookService.getOrderBook("ETH/USDT")\n');
    
    const orderBook = await orderBookService.getOrderBook('ETH/USDT');
    
    console.log('✅ Successfully fetched ETH/USDT order book!');
    console.log('📊 Order Book Summary:');
    console.log('======================');
    console.log(`Pair: ${orderBook.pair}`);
    console.log(`Last Price: $${orderBook.lastPrice}`);
    console.log(`24h Volume: ${orderBook.volume24h.toLocaleString()} ETH`);
    console.log(`24h Change: ${orderBook.change24h > 0 ? '+' : ''}${orderBook.change24h}%`);
    console.log(`Spread: $${orderBook.spread}`);
    console.log(`Total Bids: ${orderBook.bids.length}`);
    console.log(`Total Asks: ${orderBook.asks.length}`);
    console.log(`Best Bid: $${orderBook.bids[0].price}`);
    console.log(`Best Ask: $${orderBook.asks[0].price}`);
    
    console.log('\n📈 Order Book Depth Analysis:');
    console.log('==============================');
    
    const totalBidVolume = orderBook.bids.reduce((sum, bid) => sum + parseFloat(bid.amount), 0);
    const totalAskVolume = orderBook.asks.reduce((sum, ask) => sum + parseFloat(ask.amount), 0);
    
    console.log(`Total Bid Volume: ${totalBidVolume.toFixed(4)} ETH`);
    console.log(`Total Ask Volume: ${totalAskVolume.toFixed(4)} ETH`);
    console.log(`Market Depth Ratio: ${(totalBidVolume / totalAskVolume).toFixed(2)}`);
    
  } catch (error) {
    console.error('❌ Demo failed:', error.message);
  }
}

// Run the demo
console.log('🎯 Demonstrating orderBookService.getOrderBook() function\n');
demoOrderBookService();