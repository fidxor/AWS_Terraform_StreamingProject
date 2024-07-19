import json
import os
import boto3
import urllib.parse
from datetime import datetime

def lambda_handler(event, context):
    print('event:')
    print(json.dumps(event, indent=2))
    
    status_code = 200
    body = {'message': 'Job 생성이 완료되었습니다.'}
    
    # Source ---------------------------------------------------
    try:
        source_s3_bucket = event['Records'][0]['s3']['bucket']['name']
        s3_key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # 지정된 경로에 있는 파일만 처리
        if not s3_key.startswith('vod/'):
            print(f"지정된 경로가 아닙니다: s3://{source_s3_bucket}/{s3_key}")
            return {
                'statusCode': 400,
                'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'message': '지정된 경로(vod/)에 있는 파일만 처리할 수 있습니다.'})
            }
        
        # 파일 경로 분석
        path_parts = s3_key.split('/')
        if len(path_parts) < 3:  # 최소한 vod/폴더/파일명 구조를 가져야 함
            return {
                'statusCode': 400,
                'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'message': '올바르지 않은 파일 경로입니다. 최소한 vod/폴더/파일명 구조여야 합니다.'})
            }
        
        base_folder = path_parts[0]
        file_name = path_parts[-1]
        content_path = '/'.join(path_parts[1:-1])  # vod와 파일명 사이의 모든 경로
        
        source_s3_key = s3_key
        source_s3 = f's3://{source_s3_bucket}/{source_s3_key}'
        source_s3_base_name = os.path.splitext(file_name)[0]
        
    except KeyError as e:
        print(f"이벤트 구조 오류: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': f'이벤트 구조 오류: {str(e)}'})
        }
    
    # Destination ---------------------------------------------------
    try:
        destination_s3 = f's3://{os.environ["DestinationBucket"]}'
        media_convert_role = os.environ['MediaConvertRole']
        region = os.environ['AWS_REGION']
    except KeyError as e:
        print(f"환경 변수 오류: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': f'환경 변수 설정 오류: {str(e)}'})
        }
    
    # Job 메타데이터 생성 ---------------------------------------------------
    job_metadata = {
        'baseFolder': base_folder,
        'contentPath': content_path,
        'fileName': file_name,
        'outputPath': f"{base_folder}/{content_path}/{source_s3_base_name}",
        'outputExtension': '.m3u8'
    }

    print('job_metadata:')
    print(json.dumps(job_metadata, indent=2))

    # MediaConvert Job 생성 ---------------------------------------------------
    try:
        with open('job.json', 'r') as file:
            job_settings = json.load(file)
        
        # 동적으로 Destination 설정
        destination = f"{destination_s3}/{job_metadata['outputPath']}/"
        job_settings['OutputGroups'][0]['OutputGroupSettings']['HlsGroupSettings']['Destination'] = destination

        # 동적으로 FileInput 설정
        job_settings['Inputs'][0]['FileInput'] = source_s3

        mc_client = boto3.client('mediaconvert', region_name=region)
        endpoints = mc_client.describe_endpoints()    
        
        client = boto3.client('mediaconvert', 
                              region_name=region, 
                              endpoint_url=endpoints['Endpoints'][0]['Url'])
        
        job = client.create_job(
            Role=media_convert_role,
            UserMetadata=job_metadata,
            Settings=job_settings
        )
        
        body['jobId'] = job['Job']['Id']
    
    except json.JSONDecodeError as json_error:
        print(f"JSON 파싱 오류: {str(json_error)}")
        status_code = 500
        body['message'] = f'job.json 파일 파싱 중 오류 발생: {str(json_error)}'
    
    except Exception as error:
        print(f"MediaConvert Job 생성 중 오류: {str(error)}")
        status_code = 500
        body['message'] = f'MediaConvert Job 생성중 에러발생: {str(error)}'

    return {
        'statusCode': status_code,
        'headers': {'Content-Type':'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(body)
    }
