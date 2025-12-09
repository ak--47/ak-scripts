#!/bin/bash

# Configuration
PROJECT_ID="mixpanel-gtm-training"
DATASET_NAME="purpose_brands_historical"
RAW_TABLE_NAME="mixpanel_raw_loader"
FINAL_VIEW_NAME="mixpanel_data"
# Using the wildcard to catch all subfolders
BUCKET_PATH="gs://orange_theory_amplitude_mixpanel/*"

echo "1. Generating Table Definition JSON manually..."

# We use python to write the JSON to avoid shell escaping/delimiter issues.
# This bypasses 'bq mkdef' flags entirely.
python3 -c "
import json
config = {
  'sourceUris': ['$BUCKET_PATH'],
  'sourceFormat': 'CSV',
  'compression': 'GZIP',
  'maxBadRecords': 0,
  'ignoreUnknownValues': True,
  'csvOptions': {
    'fieldDelimiter': '\u00ff',  # The 'fake' delimiter to capture the whole row
    'quote': '',                 # Disable quoting
    'encoding': 'UTF-8'
  },
  'schema': {
    'fields': [
      {'name': 'row', 'type': 'STRING'}
    ]
  }
}
print(json.dumps(config))
" > table_def.json

# Safety check
if [ ! -s table_def.json ]; then
  echo "Error: Failed to create table definition file. Exiting."
  exit 1
fi

echo "2. Creating/Updating the External Table..."
# We pass the definition file directly. 
# Note: We don't need to pass schema flags because it's embedded in the JSON now.
bq mk --table \
  --external_table_definition=table_def.json \
  --project_id=$PROJECT_ID \
  $DATASET_NAME.$RAW_TABLE_NAME

echo "3. Creating the View..."
QUERY="
CREATE OR REPLACE VIEW \`$PROJECT_ID.$DATASET_NAME.$FINAL_VIEW_NAME\` AS
SELECT
  REGEXP_EXTRACT(_FILE_NAME, r'gs://[^/]+/([^/]+)/') AS folder,
  REGEXP_EXTRACT(_FILE_NAME, r'.*/([^/]+)$') AS filename,
  row
FROM
  \`$PROJECT_ID.$DATASET_NAME.$RAW_TABLE_NAME\`
WHERE
  _FILE_NAME LIKE '%.json.gz'
"

bq query --use_legacy_sql=false --project_id=$PROJECT_ID "$QUERY"

echo "Done! Query your data at: $DATASET_NAME.$FINAL_VIEW_NAME"
rm table_def.json