// Local configuration for DUniter networks
export const DUNITER_CONFIG = {
  // DUniter gtest network
  gtest: {
    name: "DUniter gtest",
    endpoint: "wss://gt.p2p.legal/ws",
    ss58Format: 4450,
    tokenSymbol: "ĞTest",
    tokenDecimals: 2,
    // Replace with actual genesis hash from gtest network
    genesisHash: "0xaf71369c9be6ab6abf3e342890ca1685a48e1e500a2ee9d38a5ae1f7d685fd7f"
  },
  // DUniter gdev network (legacy)
  gdev: {
    name: "DUniter gdev", 
    endpoint: "wss://gdev.p2p.legal/ws",
    ss58Format: 42,
    tokenSymbol: "ĞDev",
    tokenDecimals: 2,
    genesisHash: "0xc184c4ccde8e771483bba7a01533d007a3e19a66d3537c7fd59c5d9e3550b6c3"
  }
};

// Export the current active network (switch from gdev to gtest)
export const ACTIVE_DUNITER_NETWORK = DUNITER_CONFIG.gtest;
