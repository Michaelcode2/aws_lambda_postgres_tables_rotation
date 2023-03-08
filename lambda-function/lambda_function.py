import os
import json
import boto3
import psycopg2
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def getCredentials():
    credential = {}

    secret_name = os.environ['secret_name']
    region_name = os.environ['region_name']
    rds_hostname = os.environ['rds_hostname']
    db_name = os.environ['db_name']

    client = boto3.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    logger.info('Obtaining secrets...')
    
    get_secret_value_response = client.get_secret_value(
        SecretId=secret_name
    )

    logger.info(f'Secrets obtained successfully from Secret "{secret_name}"')
    
    secret = json.loads(get_secret_value_response['SecretString'])

    credential['username'] = secret['username']
    credential['password'] = secret['password']
    credential['host'] = rds_hostname
    credential['db'] = db_name

    return credential


def lambda_handler(event, context):

    # Open json config file
    try:
        with open("config.json", "r") as configfile:
            config = json.load(configfile)
            logger.info("Successfully loaded config.json file")
    except EnvironmentError: # parent of IOError, OSError
        logger.info("Unable to load config file")
        exit()

    # Get credentials from AWS Secrets
    credential = getCredentials()

    # Connect to Postgres DB
    try:
        connection = psycopg2.connect(
            user = credential['username'],
            password = credential['password'],
            host = credential['host'],
            database = credential['db']
        )
        logger.info(f"Successfully connected to host: {credential['host']}; DB: {credential['db']}")
    except Exception as e:
        logger.info(f"ERROR connection to host: {credential['host']}; DB: {credential['db']}")
        raise e

    # Tables loop from config file
    for config_table in config:
        
        logger.info(f"DB Archiving Table: {config_table['TABLE_NAME']}")
        
        cursor = connection.cursor()
        cursor.execute("SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name='{}')".format(
                        config_table["TABLE_NAME"]+"_archived"))
        if not cursor.fetchone()[0]:
            create_table_query = "CREATE TABLE PUBLIC.{}_archived (LIKE PUBLIC.{})".format(
                config_table["TABLE_NAME"],config_table["TABLE_NAME"])
            cursor.execute(create_table_query)
            logger.info(f"DB Created table: {config_table['TABLE_NAME']}_archived")

        count_cursor = connection.cursor()
        where_clause = config_table["WHERE_CLAUSE"]["WHERE_KEYS"]
        count_query = "SELECT COUNT(*) FROM {} WHERE {}"
        final_count_query = count_query.format(config_table["TABLE_NAME"], where_clause)
        count_cursor.execute(final_count_query)

        while count_cursor.fetchone()[0] > 0:
            insert_cursor = connection.cursor()
            insert_query = "INSERT INTO {}_archived SELECT * FROM {} WHERE {} LIMIT {} RETURNING {}"
            final_insert_query = insert_query.format(
                config_table["TABLE_NAME"],
                config_table["TABLE_NAME"],
                where_clause,
                config_table["WHERE_CLAUSE"]["LIMIT"],
                config_table["WHERE_CLAUSE"]["KEY"]
            )
            insert_cursor.execute(final_insert_query)
            connection.commit()

            insert_count = insert_cursor.rowcount
            logger.info(f"DB Successfully copied to {config_table['TABLE_NAME']}_archived {insert_count} records")

            if insert_count > 0:
                delete_cursor = connection.cursor()
                delete_query = "WITH row_batch AS (SELECT * FROM {} WHERE {} LIMIT {}) DELETE FROM {} o USING row_batch b WHERE b.{} = o.{} RETURNING o.{}"
                final_delete_query = delete_query.format(
                    config_table["TABLE_NAME"],
                    where_clause,
                    config_table["WHERE_CLAUSE"]["LIMIT"],
                    config_table["TABLE_NAME"],
                    config_table["WHERE_CLAUSE"]["KEY"],
                    config_table["WHERE_CLAUSE"]["KEY"],
                    config_table["WHERE_CLAUSE"]["KEY"]
                )
                delete_cursor.execute(final_delete_query)
                connection.commit()
                delete_count = delete_cursor.rowcount
                logger.info(f"DB Successfully deleted in {config_table['TABLE_NAME']} {delete_count} records")
                
                count_cursor.execute(final_count_query)

    # Return a success message
    return {
        'statusCode': 200,
        'body': 'DB tables rotated successfully'
    }
