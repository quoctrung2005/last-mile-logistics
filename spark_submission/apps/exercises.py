"""Bài 9,10,12,15,18,19,20,22,25. Run by spark-submit or import in notebooks."""
from pathlib import Path
import os, re, time, csv, json, statistics
from pyspark.sql import functions as F
DATA = Path(os.environ.get("SPARK_LAB_DATA", "/data"))
OUT = Path(os.environ.get("SPARK_LAB_OUT", "/results"))
def save(df,name):
    df.coalesce(1).write.mode("overwrite").option("header",True).csv(str(OUT/name))
def wc(sc,documents):
    return (sc.parallelize(documents,2).flatMap(lambda s: re.findall(r"[a-z0-9]+",s.lower()))
            .map(lambda w:(w,1)).reduceByKey(lambda a,b:a+b))
def run(spark,n):
    sc=spark.sparkContext
    print("\n=== BAI",n,"===")
    if n==9:
        r=sc.parallelize(range(1,21),2)
        ans={'sum':r.sum(),'mean':r.mean()};print(ans);assert ans=={'sum':210,'mean':10.5}
    elif n in (10,20):
        limit=1_000_000 if n==10 else 5_000_000
        records=[]
        for trial in range(1,(1 if n==10 else 3)+1):
            t=time.perf_counter();a=sum(range(1,limit+1));tp=time.perf_counter()-t
            t=time.perf_counter();b=sc.parallelize(range(1,limit+1),2).sum();ts=time.perf_counter()-t
            assert a==b==limit*(limit+1)//2
            records.append((trial,tp,ts,a,b))
        OUT.mkdir(parents=True,exist_ok=True)
        with (OUT/f'benchmark_{n}.csv').open('w',newline='') as f:
            w=csv.writer(f);w.writerow(['trial','python_seconds','spark_seconds','python_sum','spark_sum']);w.writerows(records)
            w.writerow(['mean',statistics.mean(r[1] for r in records),statistics.mean(r[2] for r in records),'',''])
        print(records)
        print('Timing includes RDD construction and sum; session startup excluded; first Spark job is cold.')
    elif n==12:
        docs=['Apache Spark is a big data framework','Spark supports distributed computing','Big data requires distributed processing','Python and Spark are useful for data analysis','Spark is powerful for big data']
        counts=wc(sc,docs)
        for label,r in [('all',counts),('without_stopwords',counts.filter(lambda x:x[0] not in {'is','and','for','are'}))]:
            result=r.sortBy(lambda x:(-x[1],x[0])).collect();print(label,result[:5])
            save(spark.createDataFrame(result,['word','count']),f'bai12_{label}')
    elif n==18:
        data=['Python is easy to learn','Spark is powerful','Python supports data science','Spark supports big data','Big data with Python and Spark']
        words=sc.parallelize(data,2).flatMap(lambda x:x.split()).map(lambda w:w.lower())
        ans={'total':words.count(),'unique':words.distinct().count(),'words':words.distinct().sortBy(lambda x:x).collect()}
        print(ans);assert ans['total']==22 and ans['unique']==13
    elif n==19:
        df=spark.read.option('header',True).schema('id INT, name STRING, class STRING, math DOUBLE, english DOUBLE').csv(str(DATA/'student_scores.csv'))
        df.show();df.filter(F.col('math')>=8).show();df.filter(F.col('class')=='IT01').show()
        avg=df.withColumn('average',(F.col('math')+F.col('english'))/2).orderBy(F.desc('average'),F.asc('id'))
        avg.show();avg.limit(3).show();save(avg,'bai19_average')
    elif n==15:
        df=spark.read.option('header',True).schema('product STRING, category STRING, quantity INT, price LONG').csv(str(DATA/'sales.csv'))
        df.show();df=df.withColumn('revenue',F.col('quantity')*F.col('price'));df.show()
        for key in ['product','category']:
            result=df.groupBy(key).agg(F.sum('revenue').alias('revenue')).orderBy(F.desc('revenue'),F.asc(key))
            result.show();save(result,'bai15_'+key)
        save(df,'bai15_details')
        assert df.agg(F.sum('revenue')).first()[0]==60100000
    elif n==22:
        df=spark.read.option('header',True).schema('order_id INT, customer STRING, product STRING, quantity INT, price LONG').csv(str(DATA/'orders.csv'))
        df.printSchema();df=df.withColumn('revenue',F.col('quantity')*F.col('price'));df.show();save(df,'bai22_orders')
        for key in ['customer','product']:
            result=df.groupBy(key).agg(F.sum('revenue').alias('revenue')).orderBy(F.desc('revenue'),F.asc(key))
            result.show();result.limit(1).show();save(result,'bai22_'+key)
        totals=df.agg(F.sum('quantity').alias('total_quantity'),F.sum('revenue').alias('total_revenue'))
        totals.show();save(totals,'bai22_totals');assert totals.first()[0]==15
    elif n==25:
        raw=spark.read.option('header',True).csv(str(DATA/'store_sales.csv'));raw.show();raw.printSchema()
        typed=(raw.withColumn('order_id',F.col('order_id').cast('int')).withColumn('quantity',F.col('quantity').cast('int'))
               .withColumn('price',F.col('price').cast('long')).withColumn('order_date',F.to_date('order_date','yyyy-MM-dd')))
        valid=(F.col('order_id').isNotNull() & (F.col('order_id')>0) & F.col('order_date').isNotNull() & (F.col('quantity')>0) & (F.col('price')>0))
        for c in ['customer','product','category']:
            valid=valid & F.col(c).isNotNull() & (F.length(F.trim(F.col(c)))>0)
        accepted=typed.filter(F.coalesce(valid,F.lit(False)))
        rejected=typed.filter(~F.coalesce(valid,F.lit(False)))
        clean=accepted.dropDuplicates(['order_id']).withColumn('revenue',F.col('quantity')*F.col('price')).cache()
        audit=spark.createDataFrame([(raw.count(),rejected.count(),accepted.count()-clean.count(),clean.count())],['input','invalid','duplicate','valid'])
        audit.show();save(audit,'bai25_audit');save(rejected,'bai25_rejected');save(clean,'bai25_clean')
        for key in ['product','category']:
            result=clean.groupBy(key).agg(F.sum('revenue').alias('revenue'),F.sum('quantity').alias('quantity')).orderBy(F.desc('revenue'),F.asc(key))
            result.show();save(result,'bai25_'+key)
        best=clean.groupBy('product').agg(F.sum('quantity').alias('quantity')).orderBy(F.desc('quantity'),F.asc('product'))
        best.limit(1).show();save(best.limit(1),'bai25_best_seller')
        total=clean.agg(F.sum('revenue').alias('total_revenue'));total.show();save(total,'bai25_total')
        rdd=clean.select('product','revenue').rdd.map(lambda r:(r[0],r[1])).reduceByKey(lambda a,b:a+b).collect()
        dataframe=clean.groupBy('product').agg(F.sum('revenue')).collect()
        assert dict(rdd)=={r[0]:r[1] for r in dataframe}
        assert clean.count()==120 and rejected.count()==4
        print('RDD and DataFrame product revenue match');clean.unpersist()
    else: raise ValueError(n)
if __name__=='__main__':
    from pyspark.sql import SparkSession
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--bai',type=int,nargs='+',default=[9,10,12,15,18,19,20,22,25]);args=p.parse_args()
    spark=SparkSession.builder.appName('Bai01-Exercises').config('spark.sql.shuffle.partitions','2').config('spark.sql.ansi.enabled','false').getOrCreate()
    spark.sparkContext.setLogLevel('WARN')
    try:
        for n in args.bai:run(spark,n)
    finally:spark.stop()
