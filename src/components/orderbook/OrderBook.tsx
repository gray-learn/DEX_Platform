import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Select,
  MenuItem,
  FormControl,
  CircularProgress,
  Alert,
  Chip,
  Grid
} from '@mui/material';
import { TrendingUp, TrendingDown } from '@mui/icons-material';
import { orderBookService, OrderBook as IOrderBook, Order, TradingPair } from '../../services/orderBookService';

const OrderBook: React.FC = () => {
  const [orderBook, setOrderBook] = useState<IOrderBook | null>(null);
  const [tradingPairs, setTradingPairs] = useState<TradingPair[]>([]);
  const [selectedPair, setSelectedPair] = useState<string>('ETH/USDT');
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [connected, setConnected] = useState<boolean>(false);

  useEffect(() => {
    const initializeOrderBook = async () => {
      try {
        // Connect to WebSocket
        await orderBookService.connect();
        setConnected(true);

        // Fetch trading pairs
        const pairs = await orderBookService.getOrderBook('ETH/USDT');
        
        // const pairs = await orderBookService.getTradingPairs();
        // setTradingPairs(pairs);

        // Fetch initial order book
        const initialOrderBook = await orderBookService.getOrderBook(selectedPair);
        setOrderBook(initialOrderBook);

        setLoading(false);
      } catch (err: any) {
        setError(err.message || 'Failed to connect to order book service');
        setLoading(false);
      }
    };

    initializeOrderBook();

    return () => {
      orderBookService.disconnect();
    };
  }, []);

  useEffect(() => {
    if (!connected) return;

    const handleOrderBookUpdate = (update: any) => {
      if (update.pair === selectedPair) {
        setOrderBook(prevOrderBook => {
          if (!prevOrderBook) return null;
          
          return {
            ...prevOrderBook,
            lastPrice: parseFloat(update.lastPrice),
            timestamp: update.timestamp,
            // Update only the first few orders for smooth UI
            bids: [
              ...update.bids.map((bid: Order, index: number) => ({
                ...bid,
                id: `bid-${index}`
              })),
              ...prevOrderBook.bids.slice(3)
            ],
            asks: [
              ...update.asks.map((ask: Order, index: number) => ({
                ...ask,
                id: `ask-${index}`
              })),
              ...prevOrderBook.asks.slice(3)
            ]
          };
        });
      }
    };

    orderBookService.subscribeToOrderBook(selectedPair, handleOrderBookUpdate);

    return () => {
      orderBookService.unsubscribeFromOrderBook(selectedPair, handleOrderBookUpdate);
    };
  }, [selectedPair, connected]);

  const handlePairChange = async (pair: string) => {
    setSelectedPair(pair);
    setLoading(true);
    
    try {
      const newOrderBook = await orderBookService.getOrderBook(pair);
      setOrderBook(newOrderBook);
    } catch (err: any) {
      setError(err.message || 'Failed to fetch order book');
    } finally {
      setLoading(false);
    }
  };

  const formatPrice = (price: string | number, pair: string) => {
    const numPrice = typeof price === 'string' ? parseFloat(price) : price;
    if (pair.includes('BTC')) return numPrice.toFixed(2);
    if (pair.includes('ETH')) return numPrice.toFixed(2);
    return numPrice.toFixed(4);
  };

  if (loading) {
    return (
      <Card sx={{ minHeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <CircularProgress />
      </Card>
    );
  }

  if (error) {
    return (
      <Card sx={{ minHeight: 600 }}>
        <CardContent>
          <Alert severity="error">{error}</Alert>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card 
      sx={{ 
        minHeight: 600,
        background: 'linear-gradient(135deg, #1e1e1e 0%, #2d2d2d 100%)',
        border: '1px solid #333',
      }}
    >
      <CardContent>
        <Box mb={3}>
          <Grid container spacing={2} alignItems="center">
            <Grid item xs={12} md={6}>
              <FormControl fullWidth>
                <Select
                  value={selectedPair}
                  onChange={(e) => handlePairChange(e.target.value)}
                  sx={{
                    color: '#fff',
                    '& .MuiOutlinedInput-notchedOutline': {
                      borderColor: '#333'
                    },
                    '&:hover .MuiOutlinedInput-notchedOutline': {
                      borderColor: '#00d4ff'
                    }
                  }}
                >
                  {tradingPairs.map((pair) => (
                    <MenuItem key={pair.pair} value={pair.pair}>
                      {pair.pair}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Grid>
            <Grid item xs={12} md={6}>
              {orderBook && (
                <Box display="flex" alignItems="center" gap={2}>
                  <Typography variant="h6" sx={{ color: '#00d4ff', fontFamily: 'monospace' }}>
                    ${formatPrice(orderBook.lastPrice, selectedPair)}
                  </Typography>
                  <Chip
                    icon={orderBook.change24h >= 0 ? <TrendingUp /> : <TrendingDown />}
                    label={`${orderBook.change24h >= 0 ? '+' : ''}${orderBook.change24h.toFixed(2)}%`}
                    color={orderBook.change24h >= 0 ? 'success' : 'error'}
                    size="small"
                  />
                  <Chip
                    label={connected ? 'Live' : 'Disconnected'}
                    color={connected ? 'success' : 'error'}
                    size="small"
                    variant="outlined"
                  />
                </Box>
              )}
            </Grid>
          </Grid>
        </Box>

        {orderBook && (
          <Grid container spacing={2}>
            {/* Order Book */}
            <Grid item xs={12}>
              <Typography variant="h6" gutterBottom sx={{ color: '#fff' }}>
                Order Book
              </Typography>
              <Grid container spacing={1}>
                {/* Asks (Sell Orders) */}
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" sx={{ color: '#f44336', mb: 1 }}>
                    Asks (Sell)
                  </Typography>
                  <TableContainer sx={{ maxHeight: 300, '&::-webkit-scrollbar': { width: '4px' }, '&::-webkit-scrollbar-thumb': { backgroundColor: '#555' } }}>
                    <Table size="small" stickyHeader>
                      <TableHead>
                        <TableRow>
                          <TableCell sx={{ color: '#999', backgroundColor: '#2d2d2d', fontSize: '0.75rem' }}>
                            Price
                          </TableCell>
                          <TableCell sx={{ color: '#999', backgroundColor: '#2d2d2d', fontSize: '0.75rem' }}>
                            Amount
                          </TableCell>
                          <TableCell sx={{ color: '#999', backgroundColor: '#2d2d2d', fontSize: '0.75rem' }}>
                            Total
                          </TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {orderBook.asks.slice().reverse().map((ask, index) => (
                          <TableRow 
                            key={`ask-${index}`}
                            sx={{ 
                              '&:hover': { backgroundColor: 'rgba(244, 67, 54, 0.1)' },
                              backgroundColor: index < 3 ? 'rgba(244, 67, 54, 0.05)' : 'transparent'
                            }}
                          >
                            <TableCell sx={{ color: '#f44336', fontFamily: 'monospace', fontSize: '0.75rem', py: 0.5 }}>
                              {formatPrice(ask.price, selectedPair)}
                            </TableCell>
                            <TableCell sx={{ color: '#fff', fontFamily: 'monospace', fontSize: '0.75rem', py: 0.5 }}>
                              {ask.amount}
                            </TableCell>
                            <TableCell sx={{ color: '#999', fontFamily: 'monospace', fontSize: '0.75rem', py: 0.5 }}>
                              {ask.total}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </TableContainer>
                </Grid>

                {/* Bids (Buy Orders) */}
                <Grid item xs={12} md={6}>
                  <Typography variant="subtitle2" sx={{ color: '#4caf50', mb: 1 }}>
                    Bids (Buy)
                  </Typography>
                  <TableContainer sx={{ maxHeight: 300, '&::-webkit-scrollbar': { width: '4px' }, '&::-webkit-scrollbar-thumb': { backgroundColor: '#555' } }}>
                    <Table size="small" stickyHeader>
                      <TableHead>
                        <TableRow>
                          <TableCell sx={{ color: '#999', backgroundColor: '#2d2d2d', fontSize: '0.75rem' }}>
                            Price
                          </TableCell>
                          <TableCell sx={{ color: '#999', backgroundColor: '#2d2d2d', fontSize: '0.75rem' }}>
                            Amount
                          </TableCell>
                          <TableCell sx={{ color: '#999', backgroundColor: '#2d2d2d', fontSize: '0.75rem' }}>
                            Total
                          </TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {orderBook.bids.map((bid, index) => (
                          <TableRow 
                            key={`bid-${index}`}
                            sx={{ 
                              '&:hover': { backgroundColor: 'rgba(76, 175, 80, 0.1)' },
                              backgroundColor: index < 3 ? 'rgba(76, 175, 80, 0.05)' : 'transparent'
                            }}
                          >
                            <TableCell sx={{ color: '#4caf50', fontFamily: 'monospace', fontSize: '0.75rem', py: 0.5 }}>
                              {formatPrice(bid.price, selectedPair)}
                            </TableCell>
                            <TableCell sx={{ color: '#fff', fontFamily: 'monospace', fontSize: '0.75rem', py: 0.5 }}>
                              {bid.amount}
                            </TableCell>
                            <TableCell sx={{ color: '#999', fontFamily: 'monospace', fontSize: '0.75rem', py: 0.5 }}>
                              {bid.total}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </TableContainer>
                </Grid>
              </Grid>
            </Grid>
          </Grid>
        )}
      </CardContent>
    </Card>
  );
};

export default OrderBook;