# Bài 01 - Apache Spark Master/Worker Docker Windows

## Trạng thái bài nộp
Đã soạn lời giải và mã nguồn cho 25/25 bài, dữ liệu, 3 notebook và kết quả đối chiếu Python thuần. **Chưa thực chạy Spark/Docker** vì môi trường không có Docker CLI, PySpark/Jupyter và JDK 17. Chưa có ảnh giao diện, notebook đã chạy hoặc benchmark thực tế. Không coi reference_results là đầu ra Spark.

## Nội dung
- Bao_cao_Bai01.pdf và Bao_cao_Bai01.md: lời giải 25 bài, sơ đồ và phân tích.
- docker-compose.yml: một Master, hai Worker apache/spark:3.5.1.
- apps/scala_exercises.scala: bài 5,6,7,8,17.
- apps/exercises.py: bài 9,10,12,15,18,19,20,22,25.
- apps/wordcount.py: bài 13,14,21,24.
- notebooks/: bài 9,18,19 (chưa chạy).
- data/: CSV đề bài, 5 văn bản và dữ liệu cửa hàng 125 dòng.
- reference_results/: kết quả đối chiếu, không phải kết quả Spark.
- results/: dành cho đầu ra Spark; evidence/: dành cho log, JSON và ảnh thật.

## Chạy toàn bộ trên Docker
1. Cài và mở Docker Desktop với Linux containers/WSL2. Nên cấp tối thiểu 4 GB RAM cho Docker. Giải nén toàn bộ ZIP trước khi chạy.
2. Mở PowerShell tại thư mục giải nén. Chạy: powershell -ExecutionPolicy Bypass -File .\Run-All.ps1
3. Script đợi hai Worker ALIVE, chạy Scala, các bài PySpark, WordCount; lưu log thật và CSV. Các cổng/container trùng cụm cũ phải được dừng trước.
4. Master http://localhost:8080; Worker 1 :8081; Worker 2 :8082. Chụp ảnh terminal, Master có 2 Worker và Completed Applications vào evidence.
5. Kiểm tra kết quả: Get-ChildItem results -Recurse. CSV Spark nằm trong thư mục part-*.csv, có _SUCCESS khi thành công.
6. Thử sự cố: powershell -ExecutionPolicy Bypass -File .\Worker-Failure.ps1. Chụp trước/trong/sau.
7. Cuối buổi: docker compose stop. Dọn container/mạng: docker compose down.

## Notebook Windows theo đề
Cài Python 3.10/3.11 và Temurin JDK 17. JAVA_HOME phải trỏ tới JDK 17; kiểm tra java -version. Không dùng Python 3.14 cho bộ Spark 3.5.1 này.
Tại thư mục bài: python -m pip install -r requirements.txt; python -m notebook. Mở 3 notebook, Run All rồi Save. Notebook chạy local[*] đúng yêu cầu Bài 9; job cluster dùng spark-submit trong Docker.

## Notebook trong Docker (lựa chọn thay thế)
docker compose up -d
docker exec -u 0 spark-master python3 -m pip install notebook==7.2.2 nbconvert==7.16.4 ipykernel==6.29.5
docker exec -u 0 spark-master bash -lc 'PYTHONPATH=/opt/spark/python:/opt/spark/python/lib/py4j-0.10.9.7-src.zip jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=600 /notebooks/Bai_09.ipynb /notebooks/Bai_18.ipynb /notebooks/Bai_19.ipynb'
Image đã có Spark và Java; cách này không thay thế minh chứng cài JDK 17 trên Windows theo đề. Có thể cần Internet để cài Jupyter.

## Job theo dõi khi mất Worker
Terminal A chạy:
docker exec spark-master /opt/spark/bin/spark-submit --master spark://spark-master:7077 --conf spark.driver.host=spark-master --conf spark.driver.bindAddress=0.0.0.0 --conf spark.executor.memory=512m --conf spark.cores.max=2 /opt/spark-apps/failure_probe.py
Terminal B chạy Worker-Failure.ps1 trong lúc job RUNNING. Theo dõi log và chụp giao diện. Không dừng cả hai Worker.

## Minh chứng còn phải bổ sung trước khi nộp đủ đề
Docker version/hello-world/ps/ps -a; ảnh Master 2 Worker và ứng dụng; bảng Worker thực tế; ảnh sau sửa lỗi; ảnh trước/trong/sau mất Worker; 3 notebook có output; benchmark_10.csv và benchmark_20.csv. Đọc log kiểm tra lỗi Scala vì REPL có thể không trả exit code khác 0 khi một lệnh bên trong lỗi. Điền thông tin sinh viên theo yêu cầu giảng viên (đề không cung cấp).

## Tài liệu kỹ thuật
https://archive.apache.org/dist/spark/docs/3.5.1/spark-standalone.html
https://archive.apache.org/dist/spark/docs/3.5.1/submitting-applications.html
