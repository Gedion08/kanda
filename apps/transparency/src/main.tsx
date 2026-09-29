import { baseSepolia, createKandaClient } from '@kanda/chain';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.js';
import { readSnapshot } from './data/snapshot.js';
import './i18n.js';
import './styles.css';

// VITE_RPC_URL overrides the public Base Sepolia endpoint (for example, a keyed provider for production traffic).
const rpcUrl = (import.meta.env.VITE_RPC_URL as string | undefined) ?? baseSepolia.defaultRpcUrl;
const client = createKandaClient(baseSepolia, rpcUrl);
const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 2, refetchOnWindowFocus: true } },
});

const root = document.getElementById('root');
if (root) {
  createRoot(root).render(
    <StrictMode>
      <QueryClientProvider client={queryClient}>
        <App
          network={baseSepolia}
          rpcLabel={new URL(rpcUrl).host}
          loadSnapshot={() => readSnapshot(client, baseSepolia)}
        />
      </QueryClientProvider>
    </StrictMode>,
  );
}
