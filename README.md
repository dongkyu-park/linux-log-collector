# 로그 수집기

## 요구사항

- 로그파일은 gzip 압축 알고리즘으로 압축된 gz파일 형태로, 1개의 파일씩 압축되어 저장된다.
- 일자별로 0~100까지의 넘버링으로 몇개의 압축파일이 존재하는지 특정 불가능하다.
- 각 API 의 수행 시간, url, API 호출 카운트를 기록해야 한다.
- 서버는 멀티스레드 환경이고, 로그 기록이 호출-결과-호출-결과 로 정형화 되어 있지 않다.
   쓰레드 hash값으로 url 호출에 대한 결과값을 찾아야 한다. -> hash값은 유일하다.
- 각 파일의 end line 이 호출 정보로 끝나는 경우가 있을 수 있다.
- 호출시간과 결과시간이 같은 API 호출도 존재한다. (정렬에 유의)

## 구현

- Path로 지정한 폴더내에 존재하는 .gz 확장자 형태의 파일을 모두 copyPath로 복사하고, 압축을 푼 뒤 모든 로그 파일의 내용을 필터링하여 등록용 파일에 넣는다.
- 등록용 파일을 한 줄씩 읽으며 flag와, 어떤 정보인 지 구분하여 새롭게 flag 를 설정한다.
    - 이전에 읽었던 line이 결과 정보이고, 이번 line이 호출 정보라면, flag 설정을 변경
    - 이전에 읽었던 line이 호출 정보이고, 이번 line이 결과 정보라면, flag 설정을 변경
    > 이전에 읽었던 line이 호출 정보이고, 이번 line이 호출 정보라면, endLine이 호출로 끝났다는 의미이므로 temp 파일에 해당 정보를 넣는다.
- 호출 정보 시간과 결과 정보 시간이 같은 2개의 line은 정렬시 -r 옵션을 주어 호출-결과-호출-결과 로 정형화 될 수 있도록 설정
- 결과로 담긴 result 파일을 가공하여 수행 시간 순으로 내림 차순 정렬하고, url 별 호출 count를 count 파일에 기록

![image](https://user-images.githubusercontent.com/81552729/204103130-845c7cb2-ed7c-41d6-af97-f247c9d0d328.png)

![image](https://user-images.githubusercontent.com/81552729/204103146-fe2d9e21-b75f-47b7-acc6-a5103f2caf27.png)

![image](https://user-images.githubusercontent.com/81552729/204103154-e9bdafc7-6d6a-4486-893e-4d23e2881ce4.png)

```bash
# 압축된 로그파일이 들어있는 폴더 경로와 복사할 폴더 설정
originPath="C:/Users/Park/Desktop"
copyPath="C:/Users/Park/Desktop/log"
tempPath="$copyPath/temp"

mkdir -p $copyPath
sleep 1
mkdir -p $tempPath
sleep 1

# 파일 생성
resultFile="$copyPath/result.txt"
countFile="$copyPath/count.txt"
tempFile="$tempPath/temp.txt"
waitingInsertFile="$tempPath/waitingInsert.txt"

if [ ! -e $waitingInsertFile ]
then
	touch $waitingInsertFile
	echo "init waitingInsert.txt ..."
	sleep 1
fi

if [ ! -e $resultFile ]
then
        touch $resultFile
        echo "init result.txt ..."
	sleep 1
fi

if [ ! -e $countFile ]
then
        touch $countFile
        echo "init count.txt ..."
	sleep 1
fi

if [ ! -e $tempFile ]
then
        touch $tempFile
        echo "init temp.txt ..."
	sleep 1
fi

# originPath 경로에 존재하는 gz 압축파일 모두 cpDestination 경로로 복사 후 압축해제
cp $originPath/*.gz $copyPath
sleep 1
gzip -d $copyPath/*.gz
sleep 1

# 기록에 필요한 호출시간, 호출 hash값, 수행 소요시간, url 정보를 뽑아 waiting 파일에 저장
# hash값으로 정렬으로 요청-결과-요청-결과 순으로 정렬함.
cat $copyPath/application_* | grep 'API' | awk '{print $1, $8, $11, $12}' >> $waitingInsertFile
sort $waitingInsertFile -k2 -r -o $waitingInsertFile

# API 호출 기록만 있고, 결과값이 존재하지 않는 경우 체크를 위한 flag 변수 설정
keepUrl=""
keepUrlInfo=""
lastCallIsResult="true"

# waiting 파일의 line을 읽어 호출정보, 결과정보를 구분하여 데이터 취합 후 result 로 저장
echo 'progress ... .. ..'

endOfLine=`cat $waitingInsertFile | wc -l`
per30=`expr $endOfLine / 10 '*' 3`
per60=`expr $per30 '*' 2`
per90=`expr $per30 '*' 3`
index=1

cat $waitingInsertFile | while read callTime hash resultTimeOrString urlOrString
do
	# progress 진행바
	if [ "$index" == "1" ]
	then
		echo -ne '#                                 (01%)\r'
	fi

	if [ "$index" == "$per30" ]
        then
                echo -ne '##########                        (30%)\r'
        fi

	if [ "$index" == "$per60" ]
        then
                echo -ne '####################              (60%)\r'
        fi

	if [ "$index" == "$per90" ]
        then
                echo -ne '###############################   (90%)\r'
        fi

	if [ "$index" == "$endOfLine" ]
        then
                echo -ne '################################  (100%)\n'
        fi

	if [[ "$urlOrString" == *"http"* ]] && [ "$lastCallIsResult" == "true" ] # line이 호출 요청 정보라면 flag 변수 lastCall false로 설정
	then
		keepUrl="$urlOrString"
		keepUrlInfo="$callTime $hash $resultTimeOrString $urlOrString"
		lastCallIsResult="false"
	elif [ "$urlOrString" == "(ms)" ] && [ "$lastCallIsResult" == "false" ] # line이 요청 결과 정보라면 flag 변수 lastCall true로 설정
	then
		echo $keepUrl $resultTimeOrString $urlOrString >> $resultFile
		keepUrl=""
		keepUrlInfo=""
		lastCallIsResult="true"
	else # else로 넘어오는 경우 호출 요청 정보가 2연속 읽힌 것. 로그의 endLine이 요청 정보로 끝나는 경우이다. temp 파일에 임시저장
		echo $keepUrlInfo > $tempFile
		keepUrl="$keepUrl"
	fi

	((index+=1))
done

# API 총 호출 횟수 구하기
awk '{print $1}' $resultFile | sort | uniq -c > $countFile

# API 호출 소요시간 내림차순 정렬
sort $resultFile -k2 -n -r -o $resultFile
# API 호출 횟수 내림차순 정렬
sort $countFile -k1 -n -r -o $countFile

# 원본 log 파일 모두 삭제
rm -rf $copyPath/*application_default.log*

# 임시 저장했던 temp 파일 내용 waiting 파일로 덮어쓰기
# 다음 log 수집 시 요청 결과 정보만 존재하는 로그를 결과 정보가 없었던 호출 요청 정보와 1:1 매핑하기 위함
cat $tempFile > $waitingInsertFile
cat /dev/null > $tempFile

echo 'done !'
```
