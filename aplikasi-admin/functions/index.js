const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.sendAspirasiNotification = functions.firestore
    .document("aspirasi/{aspirasiId}")
    .onCreate(async (snap, context) => {
      const newValue = snap.data();
      const namaSiswa = newValue.nama || newValue.namaSiswa || "Siswa";
      const kategori = newValue.kategori || "Pengaduan";

      const tokenDoc = await admin.firestore().collection("settings").doc("admin_token").get();
      if (!tokenDoc.exists) {
        console.log("Token admin tidak ditemukan.");
        return null;
      }

      const fcmToken = tokenDoc.data().fcmToken;

      const message = {
        token: fcmToken,
        notification: {
          title: "🚨 Ada Laporan Baru Masuk!",
          body: `${namaSiswa} mengirim pengaduan baru kategori: ${kategori}`,
        },
        webpush: {
          fcmOptions: {
            link: "https://pengaduansekolah-eb875.web.app"
          }
        }
      };

      try {
        await admin.messaging().send(message);
        console.log("Notifikasi sistem berhasil dikirim!");
      } catch (error) {
        console.log("Gagal mengirim notifikasi:", error);
      }
      return null;
    });
