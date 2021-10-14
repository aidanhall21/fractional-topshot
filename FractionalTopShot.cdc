import TopShot from 0xTOPSHOT
import FractionalTopShotUtilityToken from 0xFRACTIONALTOPSHOTUTILITYCOIN
import FungibleToken from 0xFUNGIBLETOKEN

pub contract FractionalTopShot {

  //This resource would contain the Fungible Tokens that represent the fractionalized moment
  //When a moment is fractionalized the owner fo that moment would receive this resource
  //Would need to build out a distribution mechanism for these tokens
  pub resource MomentTokens {
    access(self) var tokenVault: @FractionalTopShotUtilityToken.Vault
    pub let tokenName: String
    pub let amountAvailable: UFix64
    pub let momentId: UInt64

    destroy () {
      destroy self.tokenVault
    }

    init (tokenVault: @FractionalTopShotUtilityToken.Vault, tokenName: String, momentId: UInt64) {
      self.tokenVault <- tokenVault
      self.amountAvailable = self.tokenVault.balance
      self.tokenName = tokenName
      self.momentId = momentId
    }
  }

  //This resource controls the auction element of Fractional after a buyout bid is submitted
  //Need to flesh out some functions and add some information getters, but the ability to bid and then settle the auction is here
  pub resource AuctionItem {
    pub var momentId: UInt64
    pub let bidVault: @FungibleToken.Vault
    pub let minimumBidIncrement: UInt32
    pub var auctionStartTime: UFix64
    pub var auctionLength: UFix64
    pub var auctionCompleted: Bool
    pub var startPrice: UFix64
    pub var currentPrice: UFix64
    //Would probably want to default these values to the person who initially fractionalized the moment
    access(self) var recipientCollectionCap: Capability<&{TopShot.MomentCollectionPublic}>
    access(self) var recipientVaultCap: Capability<&{FungibleToken.Receiver}>

    init(momentId: UInt64, bidVault: @FungibleToken.Vault) {
      self.momentId = momentId
      self.auctionCompleted = false
      self.bidVault <- bidVault
      self.minimumBidIncrement = 1
      self.auctionStartTime = getCurrentBlock().timestamp
      self.auctionLength = 604800.0 //default to a week
      self.startPrice = self.bidVault.balance
      self.currentPrice = self.startPrice
    }

    pub fun settleAuction() {

      pre {
          !self.auctionCompleted : "This auction has already been settled"
      }

      //sends the NFT to the winner's collection using the collection capability in the recipientCollectionCap variable    
      self.sendNFTToWinner()
      self.auctionCompleted = true

      //Would need to build in functions allowing owners of the token to redeem for Flow etc.
    }

    pub fun placeBid(bidTokens: @FungibleToken.Vault, vaultCap: Capability<&{FungibleToken.Receiver}>, collectionCap: Capability<&{TopShot.MomentCollectionPublic}>) {

      pre {
        !self.auctionCompleted : "The auction is already settled"
        self.timeRemaining() > 0.0 : "Time to place bids has elapsed"
        bidTokens.balance >= self.minNextBid() : "Bid amount must be larger than the current price"
      }

      //function to send Flow tokens back to previous bidder
      self.releasePreviousBid()
      self.bidVault.deposit(from: <-bidTokens)
      self.recipientVaultCap = vaultCap
      self.recipientCollectionCap = collectionCap
      self.currentPrice = self.bidVault.balance

      //function to extend the auction if less than ten minutes remain
      if self.timeRemaining() < 600.0 {
        let timeToExtend = (600.0 as Fix64) - self.timeRemaining()
        self.extendWith(UFix64(timeToExtend))
      }
    }
  }

  //This resource holds fractionalized moments and keeps track of all auctions
  //Still need to add a good way to calculate the "reserve" price
  pub resource FractionalVault {

    access(self) var moments: @{UInt64: TopShot.NFT}
    access(self) var auctions: @{UInt64: AuctionItem}

    //When this function is called the moment is added to this Vault resource
    //Generic "Fractional Tokens" are minted and a MomentTokens resource is created and returned with the specified supply and token name
    pub fun addMomentToVault(moment: @TopShot.NFT, tokenSupply: UFix64, tokenName: String): @MomentTokens {

      let momentId = moment.id
      let oldMoment <- self.moments[moment.id] <- moment
      destroy oldMoment
      let mintedTokens <- FractionalTopShotUtilityToken.mintTokens(amount: tokenSupply)
      let momentTokensResource <- create MomentTokens(tokenVault: <- mintedTokens, tokenName: tokenName, momentId: momentId)
      return <- momentTokensResource

    }

    //Calling this function with enough Flow will trigger an auction
    pub fun buyout(flowVault: FlowToken.Vault, momentId: UInt64) {
      //check the balance of vault is greater or equal than the current buyout price
      //then initiate an auction

      let auction <- create AuctionItem(momentId: momentId, startPrice: flowVault.balance)

      let oldAuction <- self.auctions[momentId] <- auction
      destroy oldAuction

    }

    destroy () {
      destroy self.moments
      destroy self.auctions
    }

    init () {
      self.moments <- {}
      self.auctions <- {}
    }
  }


}
