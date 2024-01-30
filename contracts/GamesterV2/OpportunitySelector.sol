/*

This smart contract inspires from GamesterSelect.sol and by reading PlatformLock and extracting traits and current state, visualises the current opportunities for a gamester and lets them "book" the job into the BookManager.

It leverages VRF to rotate opportunities blending CCIP and Keepers to create a consistently changing state of randomisation that mix up how they get selected, sometimes favouring certain traits over others.

*/