import { PoolList } from '@/components/PoolList'
import { Header } from '@/components/Header'
import { WagmiProvider } from '@/components/WagmiProvider'

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col p-12 gap-12">
      <WagmiProvider>
        <Header />
        <PoolList />
      </WagmiProvider>
    </main>
  )
}
