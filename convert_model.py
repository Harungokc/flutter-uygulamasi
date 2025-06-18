import tensorflow as tf
import tensorflow_hub as hub # Bu artık gerekli değil, çünkü model yerelden yüklenecek
import os
import shutil

# Modelin kaydedildiği yerel SavedModel dizini
# Bu dizini indirdiğiniz saved_model.pb ve variables klasörünü içeren dizin olarak ayarlayın
# Örneğin: 'your_flutter_project/saved_model_files'
local_saved_model_path = 'saved_model_files' # Flutter projenizin ana dizinindeki klasör adı

output_dir = 'assets/models'
output_path = os.path.join(output_dir, 'mobilenet_v2_035_128_classification.tflite')

os.makedirs(output_dir, exist_ok=True) # assets/models klasörünü oluştur

print(f"Yerel SavedModel '{local_saved_model_path}' konumundan yüklüyor...")
try:
    # 1. Yerel SavedModel'ı yükle
    loaded_model = tf.saved_model.load(local_saved_model_path)

    # Modelin varsayılan çağrı imzasını (signature) al
    # Genellikle 'serving_default' anahtarı kullanılır.
    # Eğer bu hata verirse, `print(loaded_model.signatures.keys())` ile mevcut imzaları kontrol edin.
    if 'serving_default' not in loaded_model.signatures:
        raise ValueError(f"Yüklenen modelde 'serving_default' imzası bulunamadı. Mevcut imzalar: {loaded_model.signatures.keys()}")

    concrete_func = loaded_model.signatures['serving_default']

    # 2. Somut fonksiyonu belirli bir giriş şekliyle izle (trace)
    # MobileNetV2 035_128 için giriş boyutu 1x128x128x3 Float32'dir
    input_shape = (1, 128, 128, 3) # Batch size 1 (veya None), 128x128, 3 kanal (RGB)
    input_spec = tf.TensorSpec(shape=input_shape, dtype=tf.float32, name='input_image') # name='input_image' eklendi

    # tf.function ile somut fonksiyonu input_spec ile yeniden izle
    concrete_func_traced = tf.function(concrete_func, input_signature=[input_spec])
    # Bu, dönüştürücünün modeli belirli bir giriş formatıyla çağırmasına yardımcı olur.

    print("Model başarıyla yüklendi ve somut fonksiyon izlendi.")

    # 3. TFLite'a dönüştürücü oluştur
    # from_concrete_functions metodunu kullanıyoruz
    converter = tf.lite.TFLiteConverter.from_concrete_functions(
        [concrete_func_traced.get_concrete_function()], # get_concrete_function() çağrısı eklendi
        # m.signatures # Bu kısım from_concrete_functions ile kullanılmaz.
    )

    # Optimizasyonlar
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    # İsteğe bağlı: Float16 niceleme (daha küçük boyut, hafif performans düşüşü)
    # converter.target_spec.supported_types = [tf.float16]

    # Eğer modeliniz özel TensorFlow operasyonları kullanıyorsa bu satırı ekleyin:
    # converter.target_spec.supported_ops = [
    #     tf.lite.OpsSet.TFL_BUILTINS,
    #     tf.lite.OpsSet.SELECT_TF_OPS
    # ]

    print("TFLite modeline dönüştürüyor...")
    tflite_model = converter.convert()

    # 4. Modeli dosyaya kaydet
    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    print(f"TFLite modeli başarıyla dönüştürüldü ve '{output_path}' konumuna kaydedildi.")

except Exception as e:
    print(f"Model dönüştürme sırasında bir hata oluştu: {e}")