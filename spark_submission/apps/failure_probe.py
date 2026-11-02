from pyspark.sql import SparkSession
import time
def slow_sum(values):
    time.sleep(15)
    yield sum(values)
spark=SparkSession.builder.appName('Worker-Failure-Probe').getOrCreate()
try:
    total=spark.sparkContext.parallelize(range(100000),20).mapPartitions(slow_sum).sum()
    assert total==4999950000
    print('Recovered result:',total)
finally:spark.stop()
