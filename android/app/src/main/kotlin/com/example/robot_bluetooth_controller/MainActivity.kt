package com.example.robot_bluetooth_controller

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "robot_bluetooth_controller/classic_bluetooth"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    @Volatile
    private var socket: BluetoothSocket? = null
    private var output: OutputStream? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPairedDevices" -> getPairedDevices(result)
                "connect" -> {
                    val address = call.argument<String>("address")
                    connect(address, result)
                }
                "disconnect" -> {
                    disconnect()
                    result.success(null)
                }
                "write" -> {
                    val message = call.argument<String>("message") ?: ""
                    write(message, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun bluetoothAdapter(): BluetoothAdapter? {
        return (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter
    }

    private fun hasBluetoothConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    private fun getPairedDevices(result: MethodChannel.Result) {
        if (!hasBluetoothConnectPermission()) {
            result.error("NO_PERMISSION", "Bluetooth connect permission is required", null)
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("NO_ADAPTER", "Bluetooth is not supported on this device", null)
            return
        }

        val devices = adapter.bondedDevices.map {
            mapOf(
                "name" to (it.name ?: "Unknown device"),
                "address" to it.address,
            )
        }
        result.success(devices)
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String?, result: MethodChannel.Result) {
        if (address.isNullOrBlank()) {
            result.error("INVALID_ADDRESS", "Bluetooth address is required", null)
            return
        }

        if (!hasBluetoothConnectPermission()) {
            result.error("NO_PERMISSION", "Bluetooth connect permission is required", null)
            return
        }

        val adapter = bluetoothAdapter()
        if (adapter == null) {
            result.error("NO_ADAPTER", "Bluetooth is not supported on this device", null)
            return
        }

        thread {
            var lastError: Throwable? = null
            try {
                disconnect()
                val device = adapter.getRemoteDevice(address)
                adapter.cancelDiscovery()

                val connectedSocket = connectWithFallbacks(device)
                socket = connectedSocket
                output = connectedSocket.outputStream
                runOnUiThread { result.success(true) }
                return@thread
            } catch (error: Throwable) {
                lastError = error
                disconnect()
            }

            runOnUiThread {
                result.error(
                    "CONNECTION_FAILED",
                    lastError?.message ?: "Unable to connect to Bluetooth SPP device",
                    null,
                )
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectWithFallbacks(device: BluetoothDevice): BluetoothSocket {
        val factories = listOf<() -> BluetoothSocket>(
            { device.createRfcommSocketToServiceRecord(sppUuid) },
            { device.createInsecureRfcommSocketToServiceRecord(sppUuid) },
            { createChannelOneSocket(device) },
        )

        var lastError: IOException? = null
        for (factory in factories) {
            val candidate = try {
                factory()
            } catch (error: IOException) {
                lastError = error
                continue
            }

            try {
                candidate.connect()
                return candidate
            } catch (error: IOException) {
                lastError = error
                try {
                    candidate.close()
                } catch (_: IOException) {
                }
            }
        }

        throw lastError ?: IOException("All Bluetooth SPP connection methods failed")
    }

    private fun createChannelOneSocket(device: BluetoothDevice): BluetoothSocket {
        val method = device.javaClass.getMethod("createRfcommSocket", Integer.TYPE)
        return method.invoke(device, 1) as BluetoothSocket
    }

    private fun write(message: String, result: MethodChannel.Result) {
        thread {
            try {
                val stream = output
                if (stream == null) {
                    runOnUiThread { result.error("NOT_CONNECTED", "Bluetooth socket is not connected", null) }
                    return@thread
                }

                stream.write(message.toByteArray(Charsets.US_ASCII))
                stream.flush()
                runOnUiThread { result.success(null) }
            } catch (error: IOException) {
                disconnect()
                runOnUiThread {
                    result.error("WRITE_FAILED", error.message ?: "Unable to write Bluetooth data", null)
                }
            }
        }
    }

    private fun disconnect() {
        try {
            output?.close()
        } catch (_: IOException) {
        }
        try {
            socket?.close()
        } catch (_: IOException) {
        }
        output = null
        socket = null
    }
}
