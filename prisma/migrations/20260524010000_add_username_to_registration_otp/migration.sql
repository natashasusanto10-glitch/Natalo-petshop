-- Tambah kolom username di RegistrationOtp supaya register flow OTP
-- bisa carry username pilihan user dari step-1 (send OTP) ke step-2
-- (verify OTP + create User). Nullable untuk backward-compat row
-- yang ada (pending OTP) tidak break setelah deploy.
ALTER TABLE "RegistrationOtp"
  ADD COLUMN "username" TEXT;
