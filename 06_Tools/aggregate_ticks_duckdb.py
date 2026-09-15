import argparse, os, shutil, duckdb, datetime
TF=((1,60),(5,300),(15,900),(30,1800),(60,3600),(240,14400),(1440,86400))
def main():
 p=argparse.ArgumentParser();p.add_argument('--ticks',required=True);p.add_argument('--market',required=True);p.add_argument('--backup',required=True);p.add_argument('--symbol-id',type=int,default=7);a=p.parse_args()
 os.makedirs(a.backup,exist_ok=True); shutil.copy2(a.market,os.path.join(a.backup,'CBEA_Market.duckdb.before.db'))
 esc=lambda x:x.replace("'","''")
 c=duckdb.connect(); c.execute(f"ATTACH '{esc(a.ticks)}' AS src (TYPE SQLITE, READ_ONLY)"); c.execute(f"ATTACH '{esc(a.market)}' AS dst (TYPE SQLITE)")
 c.execute('DELETE FROM dst.Bars WHERE SymbolID=?',(a.symbol_id,))
 start=int(datetime.datetime(2014,1,1,tzinfo=datetime.timezone.utc).timestamp()); end=int(datetime.datetime(2027,1,1,tzinfo=datetime.timezone.utc).timestamp()); step=180*86400
 for lo in range(start,end,step):
  hi=min(lo+step,end)
  for tf,sec in TF:
   c.execute(f'''INSERT INTO dst.Bars(SymbolID,TimeframeID,OpenTime,Open,High,Low,Close,TickVolume,RealVolume,Spread,Session,Weekday,Month,Quarter,DST,BrokerOffset,DataSourceID,ImportBatchID,ImportedAt)
    SELECT SymbolID,{tf},(BrokerTime/{sec})*{sec},arg_min(price,ord),max(price),min(price),arg_max(price,ord),sum(COALESCE(Volume,0)),0,avg(CASE WHEN Ask>0 AND Bid>0 THEN Ask-Bid ELSE 0 END),0,0,0,0,0,0,0,0,now()
    FROM (SELECT SymbolID,BrokerTime,Milliseconds,TickID,Bid,Ask,Last,Volume,COALESCE(NULLIF(Last,0),Bid) price,BrokerTime*1000000+Milliseconds*1000+TickID ord FROM src.Ticks WHERE SymbolID={a.symbol_id} AND BrokerTime>={lo} AND BrokerTime<{hi}) x GROUP BY SymbolID,(BrokerTime/{sec})*{sec}''')
   c.commit()
  print('CHUNK',datetime.datetime.fromtimestamp(lo,datetime.timezone.utc).date(),flush=True)
 c.close(); print('COMPLETE',flush=True)
if __name__=='__main__':main()
