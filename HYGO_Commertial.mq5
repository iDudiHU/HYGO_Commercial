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

//--- Custom class for storing position details
class CStoredPositionInfo : public CObject {
public:
    ulong m_ticket;
    string m_symbol;
    double m_volume;
    ENUM_POSITION_TYPE m_type;
    double m_price_open;

    CStoredPositionInfo(ulong ticket, string symbol, double volume, ENUM_POSITION_TYPE type, double priceOpen)
        : m_ticket(ticket), m_symbol(symbol), m_volume(volume), m_type(type), m_price_open(priceOpen) {}
};

//--- Custom class for managing position info array
template<typename T>
class CVector : public CArrayObj {
public:
    T *operator[](const int index) const { return (T *)At(index); }
};

class CPositionVector : public CVector<CStoredPositionInfo> {
public:
    void AddPosition(ulong ticket, string symbol, double volume, ENUM_POSITION_TYPE type, double priceOpen)
    {
        CStoredPositionInfo *newPosition = new CStoredPositionInfo(ticket, symbol, volume, type, priceOpen);
        Add(newPosition);
    }

    void RemovePosition(ulong ticket)
    {
        for (int i = 0; i < Total(); i++)
        {
            CStoredPositionInfo *filePos = (this)[i];
            if (filePos.m_ticket == ticket)
            {
                delete filePos;
                Delete(i);
                break;
            }
        }
    }

    ~CPositionVector()
    {
        for (int i = 0; i < Total(); i++)
        {
            delete At(i);
        }
    }
};

// PROPFIRM: Main mode that can run independently, there may be only one instance of the program running as mode Propfirm
// MODE_REAL_MONEY: Mode that follows the propfirm farming start, it places the opposite trade, scaled proportionally.
// SHADOW: Mode that just copies trades 1:1
//--- Variables
enum ENUM_MODE
{
    MODE_PROPFIRM, //Propfirm account
    MODE_REAL_MONEY,    //Real account 
    MODE_SHADOW    // Copy
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
input double profitTarget = 0.1; // Percent we want more back than cost.
input double maxDrawDown = 0.05; // There is a daily too but we don't worry about it right now.
input double propfirmAccountSize = 100000;
input double realAccountSize = 3000;
input double BuyInCost = 500;
input ENUM_MODE Mode = MODE_REAL_MONEY;
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
    //Opening the file with Write than closing it clears the file.
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

void RewritePositionFile()
{
    int file = FileOpen(FILE_NAME, FILE_WRITE | FILE_BIN | FILE_COMMON);
    if (file != INVALID_HANDLE)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            CPositionInfo pos;
            if (pos.SelectByIndex(i))
            {
                WritePositionToFile(file, pos);
            }
        }
        FileClose(file);
    }
    
    // Log the current state of positions in the file
    Print("[RewritePositionFile] Current positions in the file:");
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        CPositionInfo pos;
        if (pos.SelectByIndex(i))
        {
            Print("Ticket: ", pos.Ticket(), ", Symbol: ", pos.Symbol(), ", Volume: ", pos.Volume(), ", Type: ", EnumToString(pos.PositionType()), ", Price Open: ", pos.PriceOpen());
        }
    }
}

void OnTimer(){
    if(Mode == MODE_PROPFIRM){
        // Clear the file and write all currently open positions to it
        RewritePositionFile();
    }else if(Mode == MODE_REAL_MONEY){
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
                        if(!TradeExists(posTicket)) {
                            trade.Buy(farmLotSize, posSymbol, 0, 0, 0, IntegerToString(posTicket));
                            Print("[MODE_REAL_MONEY] Opened BUY trade for symbol: ", posSymbol, " with lot size: ", farmLotSize, ", original ticket: ", posTicket);
                        }
                    } else if(farmType == POSITION_TYPE_SELL){
                        if(!TradeExists(posTicket)) {
                            trade.Sell(farmLotSize, posSymbol, 0, 0, 0, IntegerToString(posTicket));
                            Print("[MODE_REAL_MONEY] Opened SELL trade for symbol: ", posSymbol, " with lot size: ", farmLotSize, ", original ticket: ", posTicket);
                        }
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
                        Print("[MODE_REAL_MONEY] Closed position with ticket: ", pos.Ticket());
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

bool TradeExists(ulong posTicket)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--){
        CPositionInfo pos;
        if(pos.SelectByIndex(i)){
            if(StringToInteger(pos.Comment()) == posTicket){
                return true;
            }
        }
    }
    return false;
}

// Function to calculate the correct lot size for the farm account based on the prop firm lot size
double CalculateFarmLotSize(double propLotSize)
{
    double farmLotSize = 1.0;
    switch (Stage)
    {
        case STAGE_ONE:
            farmLotSize = BuyInCost * (1.0 + profitTarget) / (propfirmAccountSize * maxDrawDown) * propLotSize; 
            //farmLotSize = propLotSize / (propfirmAccountSize * profitTarget) * realAccountSize;
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
