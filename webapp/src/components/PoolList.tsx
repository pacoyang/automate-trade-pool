'use client'

import { useState } from 'react'
import { parseUnits, parseAbi } from 'viem'
import { useWalletClient } from 'wagmi'

import {
  Card,
  CardBody,
  Typography,
  Avatar,
  Chip,
  Button,
  Dialog,
  Input,
  CardFooter,
  Alert,
} from '@/components/material-tailwind'
import { MdGridOn, MdOutlineStackedLineChart, MdOutlineQueryBuilder } from 'react-icons/md'

const abis = [
  // 'struct PoolKey { address; address; uint24; int24; address }',
  // 'function placeOrder(PoolKey key, int24 minTick, int24 maxTick, uint24 gridStep, uint24 gridNum, uint256 gridAmount, uint256 amountIn, bool zeroForOne) external returns (uint256)'
  'function placeOrder() external returns (uint256)'
]

const TABLE_HEAD = ['#', 'Pool', 'TVL', 'Volume 24H', 'Volume 7D', 'More']

const TABLE_ROWS = [
  {
    id: 1,
    pool: 'USDC/ETH',
    tvl: '$72.79m',
    volume_24h: '$37.98m',
    volume_7d: '$163.36m'
  },
]

export function PoolList() {
  const [open, setOpen] = useState(false)
  const [shown, setShown]= useState(false)

  const handleSubmit = () => {
    setOpen(false)
    setShown(true)
    setTimeout(() => {
      setShown(false)
    }, 5000)
  }

  return (
    <>
      <Alert className="mb-4" color="green" open={shown} onClose={() => setShown(false)}>
        Created Successfully.
      </Alert>
      <TradeDialog open={open} handleOpen={() => setOpen(!open)} onSubmit={handleSubmit} />
      <Card className="h-full w-full">
        <table className="w-full min-w-max table-auto text-left">
          <thead>
            <tr>
              {TABLE_HEAD.map((head) => (
                <th
                  key={head}
                  className="border-b border-blue-gray-100 bg-blue-gray-50 p-4"
                >
                  <Typography
                    variant="small"
                    color="blue-gray"
                    className="font-normal leading-none opacity-70"
                  >
                    {head}
                  </Typography>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {TABLE_ROWS.map(({ id, pool, tvl, volume_24h, volume_7d }, index) => {
              const isLast = index === TABLE_ROWS.length - 1
              const classes = isLast ? 'p-4' : 'p-4 border-b border-blue-gray-50'
 
              return (
                <tr key={`${id}`}>
                  <td className={classes}>
                    <Typography
                      variant="small"
                      color="blue-gray"
                      className="font-normal"
                    >
                      {id}
                    </Typography>
                  </td>
                  <td className={classes}>
                    <div className="flex items-center gap-3">
                      <div className="flex items-center">
                        <Avatar src="/logo-usdc.png" alt={pool} size="xs" />
                        <Avatar src="/logo-eth.png" alt={pool} size="xs" />
                      </div>
                      <Typography
                        variant="small"
                        color="blue-gray"
                        className="font-normal"
                      >
                        {pool}
                      </Typography>
                      <Chip size="sm" variant="ghost" value="0.05%" />
                    </div>
                  </td>
                  <td className={classes}>
                    <Typography
                      variant="small"
                      color="blue-gray"
                      className="font-normal"
                    >
                      {tvl}
                    </Typography>
                  </td>
                  <td className={classes}>
                    <Typography
                      variant="small"
                      color="blue-gray"
                      className="font-normal"
                    >
                      {volume_24h}
                    </Typography>
                  </td>
                  <td className={classes}>
                    <Typography
                      variant="small"
                      color="blue-gray"
                      className="font-normal"
                    >
                      {volume_7d}
                    </Typography>
                  </td>
                  <td className={classes}>
                    <Button
                      variant="outlined"
                      size="sm"
                      onClick={() => setOpen(true)}
                    >
                      trade
                    </Button>
                    <Button
                      variant="text"
                      size="sm"
                      className="ml-2"
                    >
                      cancel trade
                    </Button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </Card>
    </>
  )
}

function TradeDialog({ open, handleOpen, onSubmit }: any) {
  const { data: walletClient, isLoading: walletIsLoading } = useWalletClient()

  const handleSubmit = async (e: any) => {
    e.preventDefault()
    const minTick = e.target.minTick.value
    const maxTick = e.target.maxTick.value
    const gridStep = e.target.gridStep.value
    const gridNum = e.target.gridNum.value
    const gridAmount = e.target.gridAmount.value
    const amountIn = e.target.amountIn.value
    console.info({
      minTick,
      maxTick,
      gridStep,
      gridNum,
      gridAmount,
      amountIn,
    })
    // @TODO: call contract method `placeOrder`
    try {
      if (walletClient) {
        await walletClient.writeContract({
          address: '0x410D5C488836D655EA47eB6D80fa926abbc24689',
          abi: parseAbi(abis),
          functionName: 'placeOrder',
          args: [],
        })
      }
    } catch (error) {
      console.error(error)
    }
    onSubmit && onSubmit()
  }

  return (
    <Dialog
      open={open}
      handler={handleOpen}
      className="bg-transparent shadow-none"
    >
      <form onSubmit={handleSubmit}>
        <Card className="mx-auto w-full">
          <CardBody className="flex flex-col gap-4">
            <Typography variant="h4" color="blue-gray">
              Place An Order
            </Typography>
            <div className="flex items-center gap-3">
              <div className="flex items-center">
                <Avatar src="/logo-usdc.png" size="xs" />
                <Avatar src="/logo-eth.png" size="xs" />
              </div>
              <Typography
                variant="small"
                color="blue-gray"
                className="font-normal"
              >
                USDC/ETH
              </Typography>
              <Chip size="sm" variant="ghost" value="0.05%" />
            </div>
            <Typography
              className="mb-3 font-normal"
              variant="paragraph"
              color="gray"
            >
              Select a strategy to place an order
            </Typography>
            <div className="flex flex-wrap gap-3">
              <div className="flex items-center justify-center gap-2 border-2 border-black py-2 px-6 rounded cursor-pointer font-semibold text-black">
                <MdGridOn size={16} />
                <div>Grid Trading</div>
              </div>
              <div className="flex items-center justify-center gap-2 border-2 py-2 px-6 rounded cursor-not-allowed font-semibold text-slate-400 border-slate-400">
                <MdOutlineStackedLineChart size={16} />
                <div>Martingale</div>
              </div>
              <div className="flex items-center justify-center gap-2 border-2 py-2 px-6 rounded cursor-not-allowed font-semibold text-slate-400 border-slate-400">
                <MdOutlineQueryBuilder size={16} />
                <div>Dollar-cost Averaging</div>
              </div>
            </div>
            <Typography className="-mb-2" variant="h6">
              Min Tick
            </Typography>
            <Input label="minTick" name="minTick" size="lg" required />
            <Typography className="-mb-2" variant="h6">
              Max Tick
            </Typography>
            <Input label="maxTick" name="maxTick" size="lg" required />
            <Typography className="-mb-2" variant="h6">
              Grid Step
            </Typography>
            <Input label="gridStep" name="gridStep" size="lg" required />
            <Typography className="-mb-2" variant="h6">
              Grid Num
            </Typography>
            <Input label="gridNum" name="gridNum" size="lg" required />
            <Typography className="-mb-2" variant="h6">
              Grid Amount
            </Typography>
            <Input label="gridAmount" name="gridAmount" size="lg" required />
            <Typography className="-mb-2" variant="h6">
              Amount In
            </Typography>
            <Input label="amountIn" name="amountIn" size="lg" required />
          </CardBody>
          <CardFooter className="pt-0">
            <Button variant="gradient" fullWidth type="submit">
              Submit
            </Button>
          </CardFooter>
        </Card>
      </form>
    </Dialog>
  )
}
