import React from 'react';
import {
  Box,
  Button,
  Card,
  CardContent,
  Typography,
  Alert,
  CircularProgress,
  Chip,
  IconButton,
  Tooltip
} from '@mui/material';
import {
  AccountBalanceWallet,
  ContentCopy,
  Logout
} from '@mui/icons-material';
import { useWeb3 } from '../../context/Web3Context';

const WalletConnect: React.FC = () => {
  const {
    account,
    balance,
    isConnected,
    isConnecting,
    error,
    connectWallet,
    disconnectWallet,
  } = useWeb3();

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const formatAddress = (address: string) => {
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  };

  if (!isConnected) {
    return (
      <Card 
        sx={{ 
          minWidth: 300,
          background: 'linear-gradient(135deg, #1e1e1e 0%, #2d2d2d 100%)',
          border: '1px solid #333',
        }}
      >
        <CardContent sx={{ textAlign: 'center', py: 4 }}>
          <AccountBalanceWallet 
            sx={{ fontSize: 48, color: '#00d4ff', mb: 2 }} 
          />
          <Typography variant="h6" gutterBottom sx={{ color: '#fff' }}>
            Connect Your Wallet
          </Typography>
          <Typography variant="body2" sx={{ color: '#999', mb: 3 }}>
            Connect your MetaMask wallet to start trading
          </Typography>
          
          {error && (
            <Alert 
              severity="error" 
              sx={{ 
                mb: 2, 
                backgroundColor: 'rgba(244, 67, 54, 0.1)',
                color: '#f44336',
                border: '1px solid rgba(244, 67, 54, 0.3)'
              }}
            >
              {error}
            </Alert>
          )}
          
          <Button
            variant="contained"
            onClick={connectWallet}
            disabled={isConnecting}
            startIcon={
              isConnecting ? (
                <CircularProgress size={20} color="inherit" />
              ) : (
                <AccountBalanceWallet />
              )
            }
            sx={{
              background: 'linear-gradient(135deg, #00d4ff 0%, #0099cc 100%)',
              color: '#000',
              fontWeight: 600,
              py: 1.5,
              px: 4,
              '&:hover': {
                background: 'linear-gradient(135deg, #0099cc 0%, #007399 100%)',
              },
              '&:disabled': {
                background: '#444',
                color: '#999'
              }
            }}
          >
            {isConnecting ? 'Connecting...' : 'Connect MetaMask'}
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card 
      sx={{ 
        minWidth: 300,
        background: 'linear-gradient(135deg, #1e1e1e 0%, #2d2d2d 100%)',
        border: '1px solid #333',
      }}
    >
      <CardContent>
        <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
          <Chip 
            icon={<AccountBalanceWallet />}
            label="Connected"
            color="success"
            variant="outlined"
            sx={{
              color: '#4caf50',
              borderColor: '#4caf50'
            }}
          />
          <Tooltip title="Disconnect">
            <IconButton 
              onClick={disconnectWallet}
              sx={{ color: '#999', '&:hover': { color: '#f44336' } }}
            >
              <Logout />
            </IconButton>
          </Tooltip>
        </Box>

        <Box mb={2}>
          <Typography variant="body2" sx={{ color: '#999', mb: 0.5 }}>
            Wallet Address
          </Typography>
          <Box display="flex" alignItems="center" gap={1}>
            <Typography variant="body1" sx={{ color: '#fff', fontFamily: 'monospace' }}>
              {formatAddress(account!)}
            </Typography>
            <Tooltip title="Copy address">
              <IconButton 
                size="small"
                onClick={() => copyToClipboard(account!)}
                sx={{ color: '#999', '&:hover': { color: '#00d4ff' } }}
              >
                <ContentCopy fontSize="small" />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>

        <Box>
          <Typography variant="body2" sx={{ color: '#999', mb: 0.5 }}>
            ETH Balance
          </Typography>
          <Typography 
            variant="h6" 
            sx={{ 
              color: '#00d4ff', 
              fontFamily: 'monospace',
              fontWeight: 600 
            }}
          >
            {parseFloat(balance).toFixed(4)} ETH
          </Typography>
        </Box>
      </CardContent>
    </Card>
  );
};

export default WalletConnect;