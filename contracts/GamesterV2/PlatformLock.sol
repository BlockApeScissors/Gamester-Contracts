/*
This is the crosschain Staking contract that allows access to the platform opportunities

It implements a rating system for Gamesters based on tasks completed.
In order to keep the rating system valuable, Gamesters have a dynamic cooldown period based on
their rating, i.e. You have 1/10 rating, when you unstake it gets reset to 5, but you are locked out
for 3 months. If you have a 8/10 rating, when you unstake it gets reset to 5 but you are locked out for 2 weeks.

If a Gamester is a bad actor, the DAO can lock their NFT inside the platform without
access to opportunities for up to 6 months. This penalty system keeps feedback at a high standard.

*/