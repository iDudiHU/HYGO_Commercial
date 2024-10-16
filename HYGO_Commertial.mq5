//+------------------------------------------------------------------+
//|                                              HYGO_Commertial.mq5 |
//|                          Copyright 2024, Tigris Digital Creative |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//--- Includes
#define FILE_NAME MQLInfoString(MQL_PROGRAM_NAME)+".bin"
#include <trade/trade.mqh>
#include <arrays/arraylong.mqh>
#include <Arrays\ArrayObj.mqh>
//--- Variables
enum ENUM_MODE
{
    MODE_PROPFIRM, // PROPFIRM: Main mode that can run independently, there may be only one instance of the program running as mode Propfirm
    MODE_FARM,     // FARM: Mode that follows the propfirm farming start, it places the opposite trade, scaled proportionally.
    MODE_SHADOW    // SHADOW: Mode that just copies trades 1:1
};
enum ENUM_TESTSTAGE
{
    STAGE_FULLY_FUNDED, // Ignore no copying
    STAGE_ONE,          // Do FARM trade with inverted order type and correct lotsize.
    STAGE_TWO,          // Do FARM trade with inverted order type and correct lotsize.
    STAGE_FUNDED,       // Do FARM trade with inverted order type and correct lotsize.
};
CTrade trade;
double LOTSTEP;
//--- input parameters
// Inputs for Propfirm Information
input double profitTarget = 0.08;
input double maxDrawDown = 0.1; // There is a daily too but we don't worry about it right now.
input double propfirmAccountSize = 100000;
input double realAccountSize = 3000;
input ENUM_MODE Mode = MODE_FARM;
input ENUM_TESTSTAGE Stage = STAGE_FULLY_FUNDED;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
    LOTSTEP = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
    EventSetMillisecondTimer(500);
    return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
    EventKillTimer();
  }

//+------------------------------------------------------------------+
//| Helper functions                                                 |
//+------------------------------------------------------------------+
void ClearFile()
{
    int file = FileOpen(FILE_NAME, FILE_WRITE | FILE_BIN | FILE_COMMON);
    if (file != INVALID_HANDLE)
    {
        FileClose(file);
    }
}

void WritePositionToFile(int file, CPositionInfo &pos)
{
    FileWriteLong(file, pos.Ticket());
    int length = StringLen(pos.Symbol());
    FileWriteInteger(file, length);
    FileWriteString(file, pos.Symbol());
    FileWriteDouble(file, pos.Volume());
    FileWriteInteger(file, pos.PositionType());
    FileWriteDouble(file, pos.PriceOpen());
}

bool PositionExistsInArray(CArrayObj<CPositionInfo> &positionsArray, ulong ticket)
{
    for(int i = 0; i < positionsArray.Total(); i++)
    {
        CPositionInfo *filePos = positionsArray.At(i);
        if(filePos.Ticket() == ticket)
        {
            return true;
        }
    }
    return false;
}
void OnTimer(){
    if(Mode == MODE_PROPFIRM){
        int file = FileOpen(FILE_NAME,FILE_WRITE|FILE_BIN|FILE_COMMON);

        if(file != INVALID_HANDLE){
            if(PositionsTotal() > 0){
                for(int i = PositionsTotal()-1; i >= 0; i--){
                    CPositionInfo pos;
                    if(pos.SelectByIndex(i)){
                        FileWriteLong(file,pos.Ticket());
                        int length = StringLen(pos.Symbol());
                        FileWriteInteger(file,length);
                        FileWriteString(file,pos.Symbol());
                        FileWriteDouble(file,pos.Volume());
                        FileWriteInteger(file,pos.PositionType());
                        FileWriteDouble(file,pos.PriceOpen());
                    }
                }
            }
            FileClose(file);
        }
    }else if(Mode == MODE_FARM){
        CArrayLong arr;
        arr.Sort();

        int file = FileOpen(FILE_NAME,FILE_READ|FILE_BIN|FILE_COMMON);
        if(file != INVALID_HANDLE){
            while(!FileIsEnding(file)){
                ulong posTicket = FileReadLong(file);
                int length = FileReadInteger(file);
                string posSymbol = FileReadString(file, length);
                double posVolume = FileReadDouble(file);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)FileReadInteger(file);
                double posPriceOpen = FileReadDouble(file);

                if(arr.SearchFirst(posTicket) < 0){
                    double farmLotSize = CalculateFarmLotSize(posVolume);
                    ENUM_POSITION_TYPE farmType = (posType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;

                    if(farmType == POSITION_TYPE_BUY){
                        trade.Buy(farmLotSize, posSymbol, 0, 0, 0, IntegerToString(posTicket));
                    } else if(farmType == POSITION_TYPE_SELL){
                        trade.Sell(farmLotSize, posSymbol, 0, 0, 0, IntegerToString(posTicket));
                    }

                    if(trade.ResultRetcode() == TRADE_RETCODE_DONE){
                        arr.InsertSort(posTicket);
                    }
                }
            }
            FileClose(file);

            for(int i = PositionsTotal()-1; i >= 0; i--){
                CPositionInfo pos;
                if(pos.SelectByIndex(i)){
                    if(arr.SearchFirst(StringToInteger(pos.Comment())) < 0){
                        trade.PositionClose(pos.Ticket());
                    }
                }
            }
        }
    }else if(Mode == MODE_SHADOW){
        CArrayLong arr;
        arr.Sort();

        int file = FileOpen(FILE_NAME,FILE_READ|FILE_BIN|FILE_COMMON);
        if(file != INVALID_HANDLE){
            while(!FileIsEnding(file)){
                ulong posTicket = FileReadLong(file);
                int length = FileReadInteger(file);
                string posSymbol = FileReadString(file, length);
                double posVolume = FileReadDouble(file);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)FileReadInteger(file);
                double posPriceOpen = FileReadDouble(file);

                for(int i = PositionsTotal()-1; i >= 0; i--){
                    CPositionInfo pos;
                    if(pos.SelectByIndex(i)){
                        if(StringToInteger(pos.Comment()) == posTicket){
                            if(arr.SearchFirst(posTicket) < 0){
                                arr.InsertSort(posTicket);
                            }
                            break;
                        }
                    }
                }
                if(arr.SearchFirst(posTicket) < 0){
                    if(posType == POSITION_TYPE_BUY){
                        trade.Buy(posVolume,posSymbol,0,0,0,IntegerToString(posTicket));
                        if(trade.ResultRetcode() == TRADE_RETCODE_DONE) arr.InsertSort(posTicket);
                    }else if(posType == POSITION_TYPE_SELL){
                        trade.Sell(posVolume,posSymbol,0,0,0,IntegerToString(posTicket));
                        if(trade.ResultRetcode() == TRADE_RETCODE_DONE) arr.InsertSort(posTicket);
                    }
                }
                FileClose(file);
                for(int i = PositionsTotal()-1; i >= 0; i--){
                    CPositionInfo pos;
                    if(pos.SelectByIndex(i)){
                        if(arr.SearchFirst(StringToInteger(pos.Comment())) < 0){
                            trade.PositionClose(pos.Ticket());
                        }
                    }
                }

            }
        }
    }
}

// Function to calculate the correct lot size for the farm account based on the prop firm lot size
double CalculateFarmLotSize(double propLotSize)
{
    double farmLotSize = 1.0;
    switch (Stage)
    {
        case STAGE_ONE:
            farmLotSize = propLotSize / (propfirmAccountSize * profitTarget) * realAccountSize;
            break;
        case STAGE_TWO:
            // Adjust the scaling to recover losses from Stage One
            farmLotSize = (propLotSize * 2) / (propfirmAccountSize * maxDrawDown) * realAccountSize;
            break;
        case STAGE_FUNDED:
            farmLotSize = propLotSize / (propfirmAccountSize * maxDrawDown) * realAccountSize;
            break;
        default:
            farmLotSize = propLotSize; // default to propLotSize if stage is not recognized
            break;
    }
    farmLotSize = MathFloor(farmLotSize/LOTSTEP) * LOTSTEP;
    Print("[CalculateFarmLotSize] Prop Lot Size: ", propLotSize, ", Calculated Farm Lot Size: ", farmLotSize);
    return farmLotSize;
}

void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
