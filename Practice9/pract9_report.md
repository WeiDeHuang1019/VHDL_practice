# FPGA 專案練習進度報告

**負責人：** 黃維得  
**目前成員：** 黃維得  
**報告日期：** 2025/08/07  
**開始日期：** 2025/05/07  
**結束日期：** 2025/09/15 

---

## 預期進度

### 五月

- **05/08 ~ 05/14**：05/14 報告第一題，開始第二題研究  
- **05/15 ~ 05/21**：開始第三題研究；05/21 第二題與第三題報告  
- **05/22 ~ 05/28**：開始第四題研究  

### 六月

- **05/29 ~ 06/04**：06/04 第四題報告  
- **06/05 ~ 06/11**：開始第五題研究  
- **06/12 ~ 06/18**：期末考週  
- **06/19 ~ 06/25**：06/25 第五題報告，開始第六題研究  

### 七月

- **06/26 ~ 07/08**：07/08 第六題報告  
- **07/09 ~ 07/15**：開始第七研究  
- **07/16 ~ 07/23**：07/16 第七題報告  
- **07/24 ~ 08/06**：第八題研究

### 八月

- **08/07 ~ 08/22**：第八題報告
- **08/25 ~ 08/29**：請假一周

### 九月
- **09/01 ~ 09/15**：第九題報告

---

## 本週報告題目：第九題 
- **16-bit LED乒乓球遊戲**
- **兩張FPGA版串接**


---

###  Breakdown

### 分為四大類別: RX, TX, synchronizer, game  
<img width="1975" height="740" alt="image" src="https://github.com/user-attachments/assets/35bd067e-6506-4aa6-a431-8e7f12c6ada1" />

---
#### **TX**
<img width="1988" height="740" alt="image" src="https://github.com/user-attachments/assets/fa7bab7b-06a8-48a1-834a-1a2495509b8e" />


---
#### **RX**
<img width="1985" height="740" alt="image" src="https://github.com/user-attachments/assets/3974331f-bcc9-4b11-a96d-4cca2d6d4faa" />


---
#### **game**
<img width="1982" height="740" alt="image" src="https://github.com/user-attachments/assets/f202eda2-2876-494f-8443-9e0234a697e1" />


---
#### **synchoronizer**
<img width="1975" height="740" alt="image" src="https://github.com/user-attachments/assets/0d8dcb4c-bf80-4df6-b6df-f457352fe5d1" />


---


## AOV   
- **模擬情境：** A發球→B回擊→A擊球失敗→顯示分數
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/51cb880d-a2cf-43ab-9db5-69e477f67afb" />


---

## MSC 

- **時序圖(一): 訊號傳遞情形**
<img width="1436" height="844" alt="image" src="https://github.com/user-attachments/assets/c878aea4-d0f6-4342-a3f3-bf20d0eb067e" />

- **時序圖(二): TX運作情形**
<img width="1456" height="877" alt="image" src="https://github.com/user-attachments/assets/657d667b-3e66-4967-99ab-37c9b7835539" />

- **時序圖(三): RX運作情形**
<img width="1086" height="866" alt="image" src="https://github.com/user-attachments/assets/149b8c12-52e5-496f-9248-c5667e85783a" />

- **時序圖(四): 整體遊戲運作情形**
<img width="1404" height="829" alt="image" src="https://github.com/user-attachments/assets/cfb13e9f-a342-4018-b20b-11168f3cc0f3" />



---
## FSM
<img width="1327" height="824" alt="image" src="https://github.com/user-attachments/assets/7fa4ea7c-7725-48c2-8776-a4a8c2a55d26" />

#### IO 線邏輯說明

- IO 線邏輯採 **Open-Drain** 設計。
- 常態為 **高阻抗狀態**。
#### 傳輸邏輯

- 當某一方 **拉低 IO 線** 時，該方即為 **TX（傳送方）**。
- TX 方可發送：
  - **長訊號**
  - **短訊號**  
  （根據拉低時間的長短分類）
#### 接收邏輯

- 高阻抗方感知到 IO 線被拉低，且識別為 **非主動拉低**。
- 即開始接收訊號，成為 **RX（接收方）**。
- 訊號分為：
  - **長訊號**
  - **短訊號**


---
## Block Diagram 
<img width="1568" height="752" alt="image" src="https://github.com/user-attachments/assets/afd011c7-fbc2-4d6b-b50e-3e8b35f637e3" />

- 所有block均為一個process, 且均接上i_clk與i_rst
  - 唯獨橘色方塊為接上除頻後的slow_clk



---
## *GPIO輸出接腳配置
<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/c148e89b-855a-4bb8-be08-f0158e9a66d4" />


- **IObus：** GPIO_2 (pin_3)  
- **共地腳：** pin_39


---

## 成果展示 – 練習題 (九) 2025/09/08

- 模擬情境 : 
  - A發球→B回擊→A回擊→B擊球失敗(過早)


### 模擬波形圖 1: 遊戲運作情形
<img width="1714" height="697" alt="image" src="https://github.com/user-attachments/assets/eb00fe36-c8ea-485a-9bcc-317359aa8e20" />

 

### 模擬波形圖 2: 球移動情形
<img width="1888" height="556" alt="image" src="https://github.com/user-attachments/assets/d47a4635-a268-40cc-9f1f-eb0191e9d33d" />


### 模擬波形圖 3: 發送訊號情形
<img width="1772" height="663" alt="image" src="https://github.com/user-attachments/assets/39971daa-1b12-44e9-b1d0-e505ef967c1f" />



### Demo影片


https://github.com/user-attachments/assets/cde21b9a-aa36-46d0-a9b1-a4815ccf666b


