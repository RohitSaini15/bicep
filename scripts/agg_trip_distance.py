"""
Spark job to aggregate taxi trip distances by date
"""
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, date_format, avg, sum, count

def main():
    # Initialize Spark session
    spark = SparkSession.builder \
        .appName("TaxiTripDistanceAggregation") \
        .getOrCreate()
    
    # Log the Spark session
    print(f"Spark session created: {spark.version}")
    
    try:
        # Read data from the bronze container
        bronze_path = "abfss://bronze@{storage_account_name}.dfs.core.windows.net/taxi-data/*.parquet"
        print(f"Reading data from: {bronze_path}")
        
        # Read the parquet files
        df = spark.read.parquet(bronze_path)
        
        # Print the schema
        print("Schema of the input data:")
        df.printSchema()
        
        # Perform aggregations
        # 1. Average trip distance by date
        avg_distance_by_date = df \
            .withColumn("trip_date", date_format(col("pickup_datetime"), "yyyy-MM-dd")) \
            .groupBy("trip_date") \
            .agg(
                avg(col("trip_distance")).alias("avg_trip_distance"),
                sum(col("trip_distance")).alias("total_trip_distance"),
                count("*").alias("trip_count")
            ) \
            .orderBy("trip_date")
        
        # Show the results
        print("Average trip distance by date:")
        avg_distance_by_date.show(20)
        
        # Write the results to the silver container
        silver_path = "abfss://silver@{storage_account_name}.dfs.core.windows.net/aggregated-taxi-data"
        print(f"Writing aggregated data to: {silver_path}")
        
        avg_distance_by_date.write \
            .mode("overwrite") \
            .parquet(silver_path)
        
        print("Aggregation job completed successfully!")
        
    except Exception as e:
        print(f"Error in Spark job: {str(e)}")
        raise
    finally:
        # Stop the Spark session
        spark.stop()

if __name__ == "__main__":
    main()