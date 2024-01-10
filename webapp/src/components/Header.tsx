'use client'

import { ConnectButton } from '@/components/ConnectButton'
import { useIsMounted } from '@/lib/hooks'

export function Header() {
  const isMounted = useIsMounted()
  return (
    <div className="flex items-center justify-between">
      <h1 className="font-mono font-medium text-lg">Automate Trade Pool</h1>
      {
        isMounted ? <ConnectButton /> : null
      }
    </div>
  )
}
