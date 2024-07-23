import json
import os
import boto3
import urllib.parse
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 환경 변수 검증
REQUIRED_ENV_VARS = ['DestinationBucket', 'MediaConvertRole', 'AWS_REGION']
for var in REQUIRED_ENV_VARS:
    if var not in os.environ:
        raise ValueError(f"Missing required environment variable: {var}")

destination_s3 = f's3://{os.environ["DestinationBucket"]}'
media_convert_role = os.environ['MediaConvertRole']
region = os.environ['AWS_REGION']

def get_mediaconvert_client():
    mc_client = boto3.client('mediaconvert', region_name=region)
    endpoints = mc_client.describe_endpoints()
    return boto3.client('mediaconvert', region_name=region, endpoint_url=endpoints['Endpoints'][0]['Url'])

def lambda_handler(event, context):
    logger.info('Event: %s', json.dumps(event, indent=2))
    
    status_code = 200
    body = {'message': 'Job 생성이 완료되었습니다.'}
    
    try:
        client = get_mediaconvert_client()
        
        source_s3_bucket = event['Records'][0]['s3']['bucket']['name']
        s3_key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        if not s3_key.startswith('vod/'):
            logger.warning(f"지정된 경로가 아닙니다: s3://{source_s3_bucket}/{s3_key}")
            return {
                'statusCode': 400,
                'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'message': '지정된 경로(vod/)에 있는 파일만 처리할 수 있습니다.'})
            }
        
        path_parts = s3_key.split('/')
        if len(path_parts) < 3:
            return {
                'statusCode': 400,
                'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'message': '올바르지 않은 파일 경로입니다. 최소한 vod/폴더/파일명 구조여야 합니다.'})
            }
        
        base_folder = path_parts[0]
        file_name = path_parts[-1]
        content_path = '/'.join(path_parts[1:-1])
        
        source_s3 = f's3://{source_s3_bucket}/{s3_key}'
        source_s3_base_name = os.path.splitext(file_name)[0]
        
        job_metadata = {
            'baseFolder': base_folder,
            'contentPath': content_path,
            'fileName': file_name,
            'outputPath': f"{base_folder}/{content_path}/{source_s3_base_name}",
            'outputExtension': '.m3u8'
        }

        logger.info('Job metadata: %s', json.dumps(job_metadata, indent=2))

        with open('job.json', 'r') as file:
            job_settings = json.load(file)
        
        destination = f"{destination_s3}/{job_metadata['outputPath']}/"
        job_settings['OutputGroups'][0]['OutputGroupSettings']['HlsGroupSettings']['Destination'] = destination
        job_settings['Inputs'][0]['FileInput'] = source_s3

        job = client.create_job(
            Role=media_convert_role,
            UserMetadata=job_metadata,
            Settings=job_settings
        )
        
        body['jobId'] = job['Job']['Id']
    
    except KeyError as e:
        logger.error(f"이벤트 구조 오류: {str(e)}")
        status_code = 400
        body['message'] = f'이벤트 구조 오류: {str(e)}'
    except json.JSONDecodeError as json_error:
        logger.error(f"JSON 파싱 오류: {str(json_error)}")
        status_code = 500
        body['message'] = f'job.json 파일 파싱 중 오류 발생: {str(json_error)}'
    except client.exceptions.AccessDeniedException as access_error:
        logger.error(f"접근 권한 오류: {str(access_error)}")
        status_code = 403
        body['message'] = f'MediaConvert 작업 생성 권한이 없습니다: {str(access_error)}'
    except Exception as error:
        logger.error(f"MediaConvert Job 생성 중 오류: {str(error)}")
        status_code = 500
        body['message'] = f'MediaConvert Job 생성중 에러발생: {str(error)}'

    return {
        'statusCode': status_code,
        'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(body)
    }