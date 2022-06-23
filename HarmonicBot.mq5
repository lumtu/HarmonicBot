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

//---------------------------------------------------------------------
// External parameters:
//---------------------------------------------------------------------

input group "iHPDetector";
input int InpLength      = 10; // Length minval=0, step=5)
input int InpErrorPercent= 10; // ErrorPercent minval=5, step=5, maxval=20)
input int InpMaxRiskPerReward = 40; // Max Risk Per Reward (Double Top/Bottom) minval=0, step=10

input group "Money management"
input bool   UseMoneyInsteadOfPercentage = false;
input bool   UseEquityInsteadOfBalance   = true; // Eigenkapital statt Balance
input double FixedBalance       = 0.0;      // FixedBalance If greater than 0, position size calculator will use it instead of actual account balance.
input double MoneyRisk          = 0.0;      // MoneyRisk Risk tolerance in base currency
input double TotalRiskInPercent = 1.0;      // Risk tolerance in percentage points
input int    LotFactor          = 1;

//---------------------------------------------------------------------
int   indicator_handle=0;

int    current_signal=0;
int    prev_signal=0;
bool   is_first_signal=true;
double g_stopLost = 0.0;
double g_takeProfit = 0.0;

double g_target1 = 0.0;

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


//---------------------------------------------------------------------
// Initialization event handler:
//---------------------------------------------------------------------
int OnInit()
{
// Create external indicator handle for future reference to it:
    ResetLastError();
    indicator_handle=iCustom(Symbol(),PERIOD_CURRENT,"iHarmonicDetector/iHPDetector", InpLength, InpErrorPercent, InpMaxRiskPerReward);

// If initialization was unsuccessful, return nonzero code:
    if(indicator_handle==INVALID_HANDLE) {
        Print("iHarmonicDetector initialization error, Code = ",GetLastError());
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
    if(CheckNewBar()!=1) {
        return;
    }

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


// Check if there is the BUY signal:
    if(CheckBuySignal(current_signal,prev_signal)==1) {
        double price = m_symbol.Ask();
        double lots = TradeSizeOptimized(price-g_stopLost);
        CTrade   trade;
        trade.PositionOpen(Symbol(),ORDER_TYPE_BUY,lots,SymbolInfoDouble(Symbol(),SYMBOL_ASK), g_stopLost, g_takeProfit);
    }

// Check if there is the SELL signal:
    if(CheckSellSignal(current_signal,prev_signal)==1) {
        double price = m_symbol.Bid();
        double lots = TradeSizeOptimized(g_stopLost-price);
        CTrade   trade;
        trade.PositionOpen(Symbol(),ORDER_TYPE_SELL,lots,SymbolInfoDouble(Symbol(),SYMBOL_BID), g_stopLost, g_takeProfit);
    }

// Save current signal:
    prev_signal=current_signal;
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
            double price = SymbolInfoDouble(Symbol(),SYMBOL_BID);
            double open = m_position.PriceOpen();
            double sl = price;
            double tp = m_position.TakeProfit();
            
            if( (price > (open+(open-sl))) ) {
                //CTrade trade;
                //trade.PositionModify(m_position.Ticket(), sl, tp);
            }
            /*
            if(target1 != 0.0 && price>target1) {
               double PositionSize = Lots / 2.0 ;
               if( PositionSize > m_symbol.LotsMin()) {
                  double LotStep = m_symbol.LotsStep();
                  PositionSize = PositionSize - MathMod(PositionSize, LotStep);

                  CTrade trade;
                  trade.PositionOpen(Symbol(),ORDER_TYPE_SELL, PositionSize, 0.0, stopLost, takeProfit);
                  target1 = 0.0;
               }
            }
            */
            return(1);
        }
        
    }

    if(_signal==-1 || _signal==0) {
        // If there is the SELL position already opened, then return:
        if(position_type==(long)POSITION_TYPE_SELL) {
            double price = m_symbol.Ask();
            double open = m_position.PriceOpen();
            double sl = price;
            double tp = m_position.TakeProfit();
            
            if( (price < (open-(sl-open))) ) {
                //CTrade trade;
                //trade.PositionModify(m_position.Ticket(), sl, tp);
            }
        
        
            /*
            double price = SymbolInfoDouble(Symbol(),SYMBOL_BID);

            if(price<target1) {
               CSymbolInfo m_symbol;
               m_symbol.Name(_Symbol);
               m_symbol.Refresh();
               double PositionSize = Lots / 2.0 ;
               if( PositionSize > m_symbol.LotsMin()) {
                  double LotStep = m_symbol.LotsStep();
                  PositionSize = PositionSize - MathMod(PositionSize, LotStep);

                  CTrade trade;
                  trade.PositionOpen(Symbol(),ORDER_TYPE_BUY, PositionSize, 0.0, stopLost, takeProfit);
                  target1 = 0.0;
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

        CSymbolInfo sym;
        sym.Name(_Symbol);
        sym.RefreshRates();
        double ask = sym.Ask();
        double bid = sym.Bid();
        double spread = ask - bid;
        
        if(type == EnHarmonic::Gartley)
        {
            double tpOffset = MathAbs(priceA[idx] - priceD[idx]) * 1.618; 
            g_target1 = priceC[idx];
            g_takeProfit = ask + tpOffset ;
            g_stopLost = priceD[idx] - spread;

            if(direction<0) {

                g_stopLost =  priceD[idx] +spread;
                g_takeProfit = bid + tpOffset ;

            }
        }
        else if(type == EnHarmonic::Crab || type == EnHarmonic::DeepCrab)
        {
            g_stopLost = priceD[idx] - spread;
            g_takeProfit = MathMax(priceA[idx], priceC[idx]);
            
            if(direction<0) {
                g_stopLost =  priceD[idx] +spread;
                g_takeProfit = MathMin(priceA[idx], priceC[idx]);
            }            
        }
        else if(type == EnHarmonic::Shark)
        {
            g_stopLost =  priceD[idx] - spread;
            g_takeProfit = priceB[idx] + ( MathAbs( priceB[idx] -  priceC[idx]) / 2.0);
            if(direction<0) {
                g_stopLost =  priceD[idx] - spread;
                g_takeProfit = priceB[idx] - ( MathAbs( priceB[idx] -  priceC[idx]) / 2.0);
            }
          
        }
        else // if(type == EnHarmonic::Bat || type == EnHarmonic::Butterfly)
        {
            g_stopLost = MathMin(priceX[idx], priceD[idx]) - spread;
            g_takeProfit = MathMax(priceA[idx], priceC[idx]);
            if(direction<0) {
                g_stopLost = MathMax(priceX[idx], priceD[idx]) - spread;
                g_takeProfit = MathMin(priceA[idx], priceC[idx]);
            }
        }
        
        double ratio = (g_takeProfit- bid) / (ask-g_stopLost);
            
        if(direction<0) {
            ratio = (ask-g_takeProfit) / (g_stopLost-bid);
        }
        
        g_stopLost = sym.NormalizePrice(g_stopLost);
        g_takeProfit = sym.NormalizePrice(g_takeProfit);
        if(ratio<2.5) {
            trend = 0;
        }
    }
    return trend;
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
