import React from 'react';
import {
  Box,
  Container,
  Grid,
  Typography,
  Paper
} from '@mui/material';
import WalletConnect from '../../components/wallet/WalletConnect';
import OrderBook from '../../components/orderbook/OrderBook';
import { Web3Provider } from '../../context/Web3Context';

const Trading: React.FC = () => {
  return (
    <Web3Provider>
      <Box 
        sx={{ 
          minHeight: '100vh',
          background: 'linear-gradient(135deg, #0f0f0f 0%, #1a1a1a 100%)',
          py: 3
        }}
      >
        <Container maxWidth="xl">
          <Box mb={4}>
            <Typography 
              variant="h3" 
              component="h1" 
              sx={{ 
                color: '#fff',
                fontWeight: 700,
                mb: 1,
                background: 'linear-gradient(135deg, #00d4ff 0%, #0099cc 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
                backgroundClip: 'text'
              }}
            >
              DEX Trading Platform
            </Typography>
            <Typography 
              variant="h6" 
              sx={{ 
                color: '#999',
                fontWeight: 400
              }}
            >
              Connect your wallet and trade cryptocurrencies in real-time
            </Typography>
          </Box>

          <Grid container spacing={3}>
            {/* Wallet Section */}
            <Grid item xs={12} lg={4}>
              <Box mb={2}>
                <Typography variant="h5" sx={{ color: '#fff', mb: 2, fontWeight: 600 }}>
                  Wallet Connection
                </Typography>
                <WalletConnect />
              </Box>
              
              {/* Trading Pairs Overview */}
              <Paper 
                sx={{ 
                  mt: 3,
                  p: 3,
                  background: 'linear-gradient(135deg, #1e1e1e 0%, #2d2d2d 100%)',
                  border: '1px solid #333',
                }}
              >
                <Typography variant="h6" sx={{ color: '#fff', mb: 2 }}>
                  Market Overview
                </Typography>
                <Box>
                  {[
                    { pair: 'ETH/USDT', price: '2,450.50', change: '+2.34%', positive: true },
                    { pair: 'BTC/USDT', price: '43,520.30', change: '+1.87%', positive: true },
                    { pair: 'BNB/USDT', price: '314.80', change: '-0.42%', positive: false },
                    { pair: 'ADA/USDT', price: '0.5825', change: '+3.21%', positive: true }
                  ].map((item, index) => (
                    <Box 
                      key={index}
                      display="flex" 
                      justifyContent="space-between" 
                      alignItems="center"
                      py={1}
                      sx={{
                        '&:not(:last-child)': {
                          borderBottom: '1px solid #333'
                        }
                      }}
                    >
                      <Typography variant="body2" sx={{ color: '#fff', fontWeight: 600 }}>
                        {item.pair}
                      </Typography>
                      <Box textAlign="right">
                        <Typography 
                          variant="body2" 
                          sx={{ color: '#00d4ff', fontFamily: 'monospace', fontWeight: 600 }}
                        >
                          ${item.price}
                        </Typography>
                        <Typography 
                          variant="caption" 
                          sx={{ 
                            color: item.positive ? '#4caf50' : '#f44336',
                            fontWeight: 600
                          }}
                        >
                          {item.change}
                        </Typography>
                      </Box>
                    </Box>
                  ))}
                </Box>
              </Paper>
            </Grid>

            {/* Order Book Section */}
            <Grid item xs={12} lg={8}>
              <Box mb={2}>
                <Typography variant="h5" sx={{ color: '#fff', mb: 2, fontWeight: 600 }}>
                  Real-time Order Book
                </Typography>
              </Box>
              <OrderBook />
            </Grid>
          </Grid>

          {/* Footer */}
          <Box mt={6} textAlign="center">
            <Typography variant="body2" sx={{ color: '#666' }}>
              Powered by Web3.js & Socket.IO • Real-time market data updates every 2 seconds
            </Typography>
          </Box>
        </Container>
      </Box>
    </Web3Provider>
  );
};

export default Trading;