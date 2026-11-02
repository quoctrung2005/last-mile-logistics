"""Bài 13,14,21,24: chung 5 tài liệu; RDD và DataFrame cùng chuẩn hóa."""
import re, argparse
from pyspark.sql import SparkSession, functions as F
p=argparse.ArgumentParser();p.add_argument('--input',default='/data/documents');p.add_argument('--output',default='/results/wordcount');args=p.parse_args()
spark=SparkSession.builder.appName('WordCount-RDD-DataFrame').config('spark.sql.shuffle.partitions','2').getOrCreate()
spark.sparkContext.setLogLevel('WARN')
try:
    rdd=(spark.sparkContext.textFile(args.input).flatMap(lambda s:re.findall(r'[a-z0-9]+',s.lower()))
         .map(lambda w:(w,1)).reduceByKey(lambda a,b:a+b))
    ranked=rdd.sortBy(lambda x:(-x[1],x[0])).collect()
    df=spark.read.text(args.input)
    tokens=df.select(F.explode(F.split(F.regexp_replace(F.lower('value'),r'[^a-z0-9]+',' '),r'\s+')).alias('word')).filter(F.col('word')!='')
    counts=tokens.groupBy('word').count().orderBy(F.desc('count'),F.asc('word'))
    assert dict(ranked)=={r['word']:r['count'] for r in counts.collect()}
    print('RDD top 10:',ranked[:10]);counts.show(10,truncate=False)
    spark.createDataFrame(ranked,['word','count']).coalesce(1).write.mode('overwrite').option('header',True).csv(args.output+'/rdd')
    counts.coalesce(1).write.mode('overwrite').option('header',True).csv(args.output+'/dataframe')
    comparison=spark.createDataFrame([(w,c,c,True) for w,c in ranked],['word','rdd_count','df_count','equal'])
    comparison.show(100,False);comparison.coalesce(1).write.mode('overwrite').option('header',True).csv(args.output+'/comparison')
finally:spark.stop()
