'use client'
import React from 'react'
import { hardhat } from 'wagmi/chains'
import { WagmiProvider as Provider, createConfig, http } from 'wagmi'
import { injected, metaMask, safe, walletConnect } from 'wagmi/connectors'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const queryClient = new QueryClient()

export const config = createConfig({
  chains: [hardhat],
  connectors: [
    injected(),
  ],
  transports: {
    [hardhat.id]: http(),
  },
})

export function WagmiProvider({ children }: { children: React.ReactNode }) {
  return (
    <Provider config={config}>
      <QueryClientProvider client={queryClient}>
        {children}
      </QueryClientProvider>
    </Provider>
  )
}
