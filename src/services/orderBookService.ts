import axios from 'axios';
import { io, Socket } from 'socket.io-client';

const BASE_URL = 'http://localhost:5025';

export interface Order {
  id?: string;
  price: string;
  amount: string;
  total: string;
  side?: 'buy' | 'sell';
}

export interface OrderBook {
  pair: string;
  lastPrice: number;
  change24h: number;
  volume24h: number;
  high24h: number;
  low24h: number;
  timestamp: string;
  bids: Order[];
  asks: Order[];
  spread: string;
}

export interface TradingPair {
  pair: string;
  lastPrice: number;
  change24h: number;
}

export class OrderBookService {
  private socket: Socket | null = null;

  constructor() {
    this.socket = io(BASE_URL, {
      autoConnect: false,
    });
  }

  // Connect to WebSocket
  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.socket) {
        reject(new Error('Socket not initialized'));
        return;
      }

      this.socket.connect();
      
      this.socket.on('connect', () => {
        console.log('Connected to order book service');
        resolve();
      });

      this.socket.on('connect_error', (error) => {
        console.error('Connection failed:', error);
        reject(error);
      });
    });
  }

  // Disconnect from WebSocket
  disconnect(): void {
    if (this.socket) {
      this.socket.disconnect();
    }
  }

  // Subscribe to order book updates for a trading pair
  subscribeToOrderBook(pair: string, callback: (data: any) => void): void {
    if (!this.socket) return;

    this.socket.emit('join_orderbook', pair);
    this.socket.on('orderbook_update', callback);
  }

  // Unsubscribe from order book updates
  unsubscribeFromOrderBook(pair: string, callback: (data: any) => void): void {
    if (!this.socket) return;

    this.socket.emit('leave_orderbook', pair);
    this.socket.off('orderbook_update', callback);
  }

  // Get initial order book data
  async getOrderBook(pair: string): Promise<OrderBook> {
    try {
      const response = await axios.get(`${BASE_URL}/api/orderbook/${pair}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching order book:', error);
      throw error;
    }
  }

  // Get all trading pairs
  async getTradingPairs(): Promise<TradingPair[]> {
    try {
      const response = await axios.get(`${BASE_URL}/api/orderbook/pairs/all`);
      return response.data;
    } catch (error) {
      console.error('Error fetching trading pairs:', error);
      throw error;
    }
  }

  // Get recent trades
  async getRecentTrades(pair: string): Promise<any> {
    try {
      const response = await axios.get(`${BASE_URL}/api/orderbook/trades/${pair}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching recent trades:', error);
      throw error;
    }
  }
}

export const orderBookService = new OrderBookService();