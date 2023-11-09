-- 連動と踏切が絡む場所の制御


-- 潮凪浜駅構内踏切
-- 下り本線（SNH_CA2）
-- 下り本線-右行（時素）
--  SNH_CA1 (45 s) and SNH1RTをSNH1Rで予約
-- 下り本線-右行（継続）
--  (SNH_CA1 and (SNH3R or SNH11R))
-- 下り本線-左行（継続）
--  (SNH_CA3 and SNH11L) or (SNH21AT and SNH21ATをSNH11Lで予約)

-- 上り本線（SNH_CB2）
-- 下り本線-右行（時素）
--  SNH_CB1 (45 s) and (SNH22TをSNH13Rで予約 or SNH4LTをSNH13Rで予約）
-- 下り本線-右行（継続）
--  (SNH_CB1 and (SNH4R or SNH12R))
-- 下り本線-左行（継続）
-- (メモ：4L・4LZ・12L・12LZ)
--  SNH21BTが左行で予約 and
--   (
--    SNH21BT or
--    (SNH21反位 and (SNH21AT or SNH_CA3)) or
--    (SNH21定位 and SNH_CB3)
--   )

-- 大森踏切(SNH21AT or SNH21BT右行かつ在線 or (SNH21BT左行 and SNH_OC))
-- 下り
--  3R, 11R, 4R, 12R
-- 上り
--  11L, 12L, 12LZ, 4LZ
--  4Lかつ接近
