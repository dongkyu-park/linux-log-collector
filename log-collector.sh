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
