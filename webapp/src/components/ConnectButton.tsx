'use client'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { injected } from 'wagmi/connectors'

import { Button, Avatar } from '@/components/material-tailwind'

export function ConnectButton() {
  const { address, isConnected } = useAccount()
  const { connect } = useConnect()
  const { disconnect } = useDisconnect()

  if (address) {
    return (
      <div className="flex flex-row gap-2.5 items-center">
        <Avatar src={'https://effigy.im/a/0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045.png'} size="xs" />
        <div>{address.slice(0, 6)}</div>
        <Button onClick={() => disconnect()} variant="text" size="sm">Disconnect</Button>
      </div>
    )
  }
  return (
    <Button
      onClick={() => isConnected ? null : connect({ connector: injected()  })}
      variant="outlined"
      size="sm"
    >
      Connect Wallet
    </Button>
  )
}
