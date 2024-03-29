//=====================================================================
// Expert based on the HeikenAshiTrendDetector trend indicator.
//=====================================================================
#property copyright  "lumtu"
#property link       "develop@lumtu.de"
#property version    "1.00"
#property description "Expert based on the iHPDetector indicator."
//---------------------------------------------------------------------
// Included libraries:
//---------------------------------------------------------------------
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Arrays\ArrayDouble.mqh>
//---------------------------------------------------------------------
// External parameters:
//---------------------------------------------------------------------

input group "iHPDetector";
input int InpLength      = 10; // Length minval=0, step=5)
input int InpErrorPercent= 10; // ErrorPercent minval=5, step=5, maxval=20)
input int InpMaxRiskPerReward = 40; // Max Risk Per Reward (Double Top/Bottom) minval=0, step=10
input double InpProfitFactor = 1.5;

input group "Money management"
input bool   UseMoneyInsteadOfPercentage = false;
input bool   UseEquityInsteadOfBalance   = true; // Eigenkapital statt Balance
input double FixedBalance       = 0.0;      // FixedBalance If greater than 0, position size calculator will use it instead of actual account balance.
input double MoneyRisk          = 0.0;      // MoneyRisk Risk tolerance in base currency
input double TotalRiskInPercent = 1.0;      // Risk tolerance in percentage points
input int    LotFactor          = 1;

ulong Expert_MagicNumber = 346772; //

//---------------------------------------------------------------------
int   indicator_handle=0;
int   indicator_SMA=0;

int    current_signal=0;
int    prev_signal=0;
bool   is_first_signal=true;
double g_stopLost = 0.0;
double g_takeProfit = 0.0;
string PatternName="";

CArrayDouble g_targets;

bool m_useMoneyInsteadOfPercentage = UseMoneyInsteadOfPercentage;
bool m_useEquityInsteadOfBalance = UseEquityInsteadOfBalance; // Eigenkapital statt Balance
double m_fixedBalance = FixedBalance;            // If greater than 0, position size calculator will use it instead of actual account balance.
double m_moneyRisk = MoneyRisk;               // Risk tolerance in base currency
double m_risk = TotalRiskInPercent;                    // Risk tolerance in percentage points
int m_lotFactor = LotFactor;


CSymbolInfo m_symbol;
CAccountInfo m_account;
CPositionInfo m_position; // trade position object

enum EnHarmonic {
    Unknown=0,
    Gartley=1,
    Crab=2,
    DeepCrab=3,
    Bat=4,
    Butterfly=5,
    Shark=6,
    Cypher=7,
    ThreeDrives=8,
    FiveZero=9
};

int m_margin_mode=0;
void SetMarginMode(void) { m_margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE); }
bool IsHedging(void) { return(m_margin_mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING); }

int g_MaPeriod = 21;
//---------------------------------------------------------------------
// Initialization event handler:
//---------------------------------------------------------------------
int OnInit()
{
   SetMarginMode();
   
// Create external indicator handle for future reference to it:
    ResetLastError();
    indicator_handle=iCustom(Symbol(),PERIOD_CURRENT,"iHarmonicDetector/iHPDetector", InpLength, InpErrorPercent, InpMaxRiskPerReward);

// If initialization was unsuccessful, return nonzero code:
    if(indicator_handle==INVALID_HANDLE) {
        Print("iHarmonicDetector initialization error, Code = ",GetLastError());
        return(-1);
    }

   indicator_SMA=iMA(_Symbol, PERIOD_CURRENT, g_MaPeriod, 0, MODE_EMA, PRICE_CLOSE);

// If initialization was unsuccessful, return nonzero code:
    if(indicator_SMA==INVALID_HANDLE) {
        Print("iMA initialization error, Code = ",GetLastError());
        return(-1);
    }


    m_symbol.Name(_Symbol);
    return(0);
}
//---------------------------------------------------------------------
// Deinitialization event handler:
//---------------------------------------------------------------------
void OnDeinit(const int _reason)
{
// Delete indicator handle:
    if(indicator_handle!=INVALID_HANDLE) {
        IndicatorRelease(indicator_handle);
    }
}


//---------------------------------------------------------------------
void OnTick()
{
// Wait for beginning of a new bar:
    // if(CheckNewBar()!=1) { return;  }

    m_symbol.Refresh();
    m_symbol.RefreshRates();
    

// Get signal to open/close position:
    current_signal=GetSignal();
    if(is_first_signal==true) {
        prev_signal=current_signal;
        is_first_signal=false;
    }

// Select position by current symbol:
    if(PositionSelect(Symbol())==true) {
        // Check if we need to close a reverse position:
        if(CheckPositionClose(current_signal)==1) {
            return;
        }
    }

   bool canOpen = true; //!SelectPosition(_Symbol);
    
// Check if there is the BUY signal:
    if(canOpen && CheckBuySignal(current_signal,prev_signal)==1) {
        double price = m_symbol.Ask();
        double lots = TradeSizeOptimized(price-g_stopLost);
        CTrade   trade;
        trade.SetExpertMagicNumber(Expert_MagicNumber);
        trade.PositionOpen(Symbol(),ORDER_TYPE_BUY,lots,SymbolInfoDouble(Symbol(),SYMBOL_ASK), g_stopLost, g_takeProfit, PatternName);
    }

// Check if there is the SELL signal:
    if(canOpen && CheckSellSignal(current_signal,prev_signal)==1) {
        double price = m_symbol.Bid();
        double lots = TradeSizeOptimized(g_stopLost-price);
        CTrade   trade;
        trade.SetExpertMagicNumber(Expert_MagicNumber);
        trade.PositionOpen(Symbol(),ORDER_TYPE_SELL,lots,SymbolInfoDouble(Symbol(),SYMBOL_BID), g_stopLost, g_takeProfit, PatternName);
    }

// Save current signal:
    prev_signal=current_signal;
}


bool SelectPosition(const string symbol)
  {
   bool res=false;
//---
   if(IsHedging())
     {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
        {
         string position_symbol=PositionGetSymbol(i);
         if(position_symbol==symbol &&   Expert_MagicNumber==PositionGetInteger(POSITION_MAGIC))
           {
            res=true;
            break;
           }
        }
     }
   else
      res=PositionSelect(symbol);
//---
   return(res);
  }


//---------------------------------------------------------------------
// Check if we need to close position:
//---------------------------------------------------------------------
// returns:
//  0 - no open position
//  1 - position already opened in signal's direction
//---------------------------------------------------------------------
int CheckPositionClose(int _signal)
{
    long position_type=PositionGetInteger(POSITION_TYPE);
    
    m_position.Select(Symbol());

    if(_signal==1 || _signal==0) {
    
        // If there is the BUY position already opened, then return:
        if(position_type==(long)POSITION_TYPE_BUY) {
            /*
            double price = m_symbol.Bid();
            double open = m_position.PriceOpen();
            double sl = m_position.StopLoss();
            double tp = m_position.TakeProfit();
            
            double partialLots = 0.0;
            if( sl < open && price > (open+(open-sl)) ) {
                double newSL = m_symbol.NormalizePrice(open + m_symbol.TickSize());
                // CTrade trade;
                // if( trade.PositionModify(m_position.Ticket(), newSL, tp) )
                {
                  partialLots = m_position.Volume() / 2.0;
                }
                // else
                {
                  // PrintFormat("Position kann nicht geändert werden");
                }
            }
            else if(g_targets.Total()>0)
            {
               int targetSize = g_targets.Total();

               g_targets.Sort(0);
               if(targetSize > 0 && price > g_targets[0]) {
                  g_targets.Delete(0);
                  
                  double lots = m_position.Volume();
                  partialLots = lots / (targetSize+1);

               }
            }
            
            if(partialLots>0.0)
            {
               double PositionSize = partialLots;
               if( PositionSize > m_symbol.LotsMin()) {
                  double LotStep = m_symbol.LotsStep();
                  PositionSize = PositionSize - MathMod(PositionSize, LotStep);
   
                  CTrade trade;
                  trade.PositionOpen(Symbol(),ORDER_TYPE_SELL, PositionSize, 0.0, 0.0, 0.0);
               }
            }
            */
            return(1);
        }
        
    }

    if(_signal==-1 || _signal==0) {
        // If there is the SELL position already opened, then return:
        if(position_type==(long)POSITION_TYPE_SELL) {
            /*
            double price = m_symbol.Ask();
            double open = m_position.PriceOpen();
            double sl = m_position.StopLoss();
            double tp = m_position.TakeProfit();
            
            double partialLots = 0.0;
            if( sl > open && (price) < (open-(sl-open)) ) {
               double newSL = m_symbol.NormalizePrice(open - m_symbol.TickSize());
                // CTrade trade;
                // if( trade.PositionModify(m_position.Ticket(), newSL, tp) )
                {
                  partialLots = m_position.Volume() / 2.0;
                }
                // else
                {
                  // PrintFormat("Position kann nicht geändert werden");
                }
            }
            else if(g_targets.Total() > 0)
            {
               int targetSize = g_targets.Total();
               g_targets.Sort(0);
               if( price < g_targets.At(targetSize-1)) {
                  g_targets.Delete(targetSize-1);
   
                  double lots = m_position.Volume();
                  partialLots = lots / (targetSize+1);
               }
            }
            
            if(partialLots>0.0)
            {
               double PositionSize = partialLots;
               if( PositionSize > m_symbol.LotsMin()) {
                  double LotStep = m_symbol.LotsStep();
                  PositionSize = PositionSize - MathMod(PositionSize, LotStep);
                  
                  CTrade trade;
                  trade.PositionOpen(Symbol(),ORDER_TYPE_BUY, PositionSize, 0.0, 0.0, 0.0);
               }
            }
            */
            return(1);
        }
    }

// Close position:
    CTrade   trade;
    trade.PositionClose(Symbol());

    return(0);
}
//---------------------------------------------------------------------
// Check if there is the BUY signal:
//---------------------------------------------------------------------
// returns:
//  0 - no signal
//  1 - there is the BUY signal
//---------------------------------------------------------------------
int CheckBuySignal(int _curr_signal,int _prev_signal)
{
// Check if signal has changed to BUY:
    if((_curr_signal==1 && _prev_signal==0) || (_curr_signal==1 && _prev_signal==-1)) {
        return(1);
    }

    return(0);
}
//---------------------------------------------------------------------
// Check if there is the SELL signal:
//---------------------------------------------------------------------
// returns:
//  0 - no signal
//  1 - there is the SELL signal
//---------------------------------------------------------------------
int CheckSellSignal(int _curr_signal,int _prev_signal)
{
// Check if signal has changed to SELL:
    if((_curr_signal==-1 && _prev_signal==0) || (_curr_signal==-1 && _prev_signal==1)) {
        return(1);
    }

    return(0);
}

//---------------------------------------------------------------------
// Get signal to open/close position:
//---------------------------------------------------------------------
#define LEN 2
//---------------------------------------------------------------------
int GetSignal()
{
    double pattern[LEN];
    double priceD[LEN];
    double priceC[LEN];
    double priceB[LEN];
    double priceA[LEN];
    double priceX[LEN];

// Get signal from trend indicator:
    ResetLastError();
    if(CopyBuffer(indicator_handle,1,0,LEN,priceD) !=LEN
       || CopyBuffer(indicator_handle,5,0,LEN,priceX) !=LEN
       || CopyBuffer(indicator_handle,4,0,LEN,priceA) !=LEN
       || CopyBuffer(indicator_handle,3,0,LEN,priceB) !=LEN
       || CopyBuffer(indicator_handle,2,0,LEN,priceC) !=LEN
       || CopyBuffer(indicator_handle,6,0,LEN,pattern) !=LEN
      ) {
        Print("CopyBuffer copy error, Code = ",GetLastError());
        return(0);
    }

   
    int idx = 0;
    int direction = pattern[idx] > 0 ? 1 : -1;
    EnHarmonic type = (EnHarmonic)MathAbs(pattern[idx]);
    if(type == EnHarmonic::Unknown) {
        idx++;
        direction = pattern[idx] > 0 ? 1 : -1;
        type = (EnHarmonic)MathAbs(pattern[idx]);
    }


    int trend = 0;

    if(type != EnHarmonic::Unknown) {
        trend = direction;
         
        PatternName = EnumToString(type);
         
        g_targets.Clear();
        
        double ask = m_symbol.Ask();
        double bid = m_symbol.Bid();
        double spread = ask - bid;
        if(spread==0.0)
            spread = m_symbol.TickSize();
        bool isNewCalculation = false;    
        if(isNewCalculation)
        {
            TryAddTarget(direction, priceA[idx]);
            TryAddTarget(direction, priceB[idx]);
            TryAddTarget(direction, priceC[idx]);

            double adDiff = MathAbs(priceA[idx] - priceD[idx]);
            double tpOffset = adDiff * 1.618; 
            TryAddTarget(direction, priceD[idx] + (tpOffset * direction) );
            
            tpOffset = adDiff * 2.24;    
            TryAddTarget(direction, priceD[idx] + (tpOffset * direction) );
            
            tpOffset = adDiff * 2.618;    
            // g_takeProfit = priceD[idx] + (tpOffset * direction);
            
            double price = ( direction>0 ? MathMax(priceD[idx], priceX[idx]) : MathMin(priceD[idx], priceX[idx]) );
            g_stopLost = price - ((spread*2.0) * direction);
            
            double diff = ((direction>0? ask : bid) - g_stopLost) *1.07;
            
            g_takeProfit = (direction>0? ask : bid) + diff;
        }
        else
        {  // old calculation
            if(type == EnHarmonic::Gartley)
            {
                double tpOffset = MathAbs(priceA[idx] - priceD[idx]) * 1.618; 
                TryAddTarget(direction, priceC[idx] );
                g_takeProfit = ask + tpOffset ;
                g_stopLost = priceD[idx] ;
    
                if(direction<0) {
    
                    g_stopLost =  priceD[idx] ;
                    g_takeProfit = bid + tpOffset ;
    
                }
            }
            else if(type == EnHarmonic::Crab || type == EnHarmonic::DeepCrab)
            {
                g_stopLost = priceD[idx] ;
                g_takeProfit = MathMax(priceA[idx], priceC[idx]);
                TryAddTarget(direction, priceC[idx] );
                
                if(direction<0) {
                    g_stopLost =  priceD[idx] ;
                    g_takeProfit = MathMin(priceA[idx], priceC[idx]);
                }            
            }
            else if(type == EnHarmonic::Shark)
            {
                TryAddTarget(direction, priceC[idx] );

                g_stopLost =  priceD[idx] ;
                g_takeProfit = priceB[idx] + ( MathAbs( priceB[idx] -  priceC[idx]) / 2.0);
                if(direction<0) {
                    g_stopLost =  priceD[idx] ;
                    g_takeProfit = priceB[idx] - ( MathAbs( priceB[idx] -  priceC[idx]) / 2.0);
                }
              
            }
            else // if(type == EnHarmonic::Bat || type == EnHarmonic::Butterfly)
            {
                TryAddTarget(direction, priceC[idx] );
            
                g_stopLost = MathMin(priceX[idx], priceD[idx]) ;
                g_takeProfit = MathMax(priceA[idx], priceC[idx]);
                if(direction<0) {
                    g_stopLost = MathMax(priceX[idx], priceD[idx]) ;
                    g_takeProfit = MathMin(priceA[idx], priceC[idx]);
                }
            }            
    
        }
        
        if(direction>0){
            g_stopLost -= m_symbol.TickSize()*10;
            g_takeProfit -= m_symbol.TickSize()*20;
        } else {
            g_stopLost += m_symbol.TickSize()*10;
            g_takeProfit += m_symbol.TickSize()*20;
        }
        
        g_stopLost   = m_symbol.NormalizePrice(g_stopLost);
        g_takeProfit = m_symbol.NormalizePrice(g_takeProfit);

        double ratio = 0.0;
        if( g_stopLost != 0.0 )
        {
            // ratio = g_takeProfit / g_stopLost;
            ratio = (g_takeProfit- bid) / (ask-g_stopLost);
                
            if(direction<0) {
                ratio = (ask-g_takeProfit) / (g_stopLost-bid);
            }
            
        }
        else 
        {
            PrintFormat("SL:%.3f | TP:%.3f", g_stopLost, g_takeProfit);
        }
        PrintFormat("RR : %.3f", ratio);
        if(ratio<InpProfitFactor) { trend = 0; }
    }
    return trend;
}

void TryAddTarget(int dir, double price)
{
   if(price<=0.0 || dir == 0)
      return;

   price = m_symbol.NormalizePrice(price);
   
   double ask = m_symbol.Ask();
   double bid = m_symbol.Bid();
   double spread = ask - bid;

   double currPrice = dir>0 ? ask : bid;
   currPrice += spread * dir;
   
   if(  (dir > 0 && price < currPrice) 
     || (dir < 0 && price > currPrice)  ) {
      return;
   }

   g_targets.Add(price);   
   
   g_targets.Sort(1);
   
}


//---------------------------------------------------------------------
// Returns flag of a new bar:
//---------------------------------------------------------------------
// - if it returns 1, there is a new bar
//---------------------------------------------------------------------
int CheckNewBar()
{
    MqlRates      current_rates[1];

    ResetLastError();
    if(CopyRates(Symbol(),Period(),0,1,current_rates)!=1) {
        Print("CopyRates copy error, Code = ",GetLastError());
        return(0);
    }

    if(current_rates[0].tick_volume>1) {
        return(0);
    }

    return(1);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double TradeSizeOptimized(double stopLoss)
{

    double Size, RiskMoney, PositionSize = 0;

    if(m_symbol.CurrencyBase() == "")
        return (0);

    if(m_fixedBalance > 0) {
        Size = m_fixedBalance;
    } else if(m_useEquityInsteadOfBalance) {
        Size = m_account.Equity();
    } else {
        Size = m_account.Balance();
    }

    if(!m_useMoneyInsteadOfPercentage) {
        RiskMoney = Size * m_risk / 100;
    } else {
        RiskMoney = m_moneyRisk;
    }

    double UnitCost = m_symbol.TickValue();
    double TickSize = m_symbol.TickSize();

    if((stopLoss != 0) && (UnitCost != 0) && (TickSize != 0)) {
        PositionSize = NormalizeDouble(RiskMoney / (stopLoss * UnitCost / TickSize), m_symbol.Digits());
    }

    PositionSize = MathMax(PositionSize, m_symbol.LotsMin());
    PositionSize = MathMin(PositionSize, m_symbol.LotsMax());

    PositionSize = m_lotFactor * PositionSize;
    double LotStep = m_symbol.LotsStep();
    PositionSize = PositionSize - MathMod(PositionSize, LotStep);

    printf("Position Size: %.3f", PositionSize);

    return (PositionSize);
}

//+------------------------------------------------------------------+
