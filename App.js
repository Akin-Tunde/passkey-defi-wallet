import { createAppKit } from '@reown/appkit/react'
import { BitcoinAdapter } from '@reown/appkit-adapter-bitcoin'
import { StacksMainnet, StacksTestnet } from '@stacks/network'

// 1. Get Project ID at https://cloud.reown.com
const projectId = 'YOUR_PROJECT_ID_HERE';

// 2. Setup Stacks Networks
const networks = [StacksMainnet, StacksTestnet];

// 3. Setup Bitcoin Adapter
const bitcoinAdapter = new BitcoinAdapter()

// 4. Create modal
createAppKit({
  adapters: [bitcoinAdapter],
  networks,
  projectId,
  metadata: {
    name: 'Passkey DeFi Wallet',
    description: 'Secure Bitcoin DeFi with WebAuthn',
    url: 'https://yourwallet.xyz',
    icons: ['https://avatars.githubusercontent.com/u/179229932']
  },
  features: {
    analytics: true // IMPORTANT: Helps with Builder Challenge tracking
  }
})

export default function App({ children }) {
  return children;
}