// MandelbrotAsm.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <iostream>
#include <thread>
//#pragma comment(lib,"opencv_world4120.lib")
#include <opencv2/opencv.hpp>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/highgui.hpp>
#include <vector>
#include <mutex>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <Windows.h>

#include <string>

#pragma warning(push)
#pragma warning(disable:4146)
#include <gmp.h>
#pragma warning(pop)

namespace fs = std::filesystem;
using namespace std;
using namespace cv;
constexpr int iWidth = 3840; // width must be divisible by 8 (anyways its hardcoded in assembly)
constexpr int iHeight = 2160;
constexpr int scale = MAX(iWidth, iHeight);

char palette[256 * 3]; // a feature I added later
using fortrandouble2 = void (*)(double rehi, double imhi, double relo, double imlo, double stephi, double steplo, int speclen, int maxitr, uint8_t* blout, uint8_t* clout);
fortrandouble2 makeRowdouble2;

inline void gmp2double2(mpf_t& in, mpf_t& tmp, double& hi, double& lo) {
    hi = mpf_get_d(in);
    mpf_set_d(tmp, hi);
    mpf_sub(tmp, in, tmp); // find error of double (in-round(in))
    lo = mpf_get_d(tmp);
}

void rowThreadDouble2(string re3, string im3, double zoom, int32_t maxitr, int32_t speclen, unsigned int threads, int id, unsigned char* H, unsigned char* V) {
    // convert to gmp
    //mpf_set_default_prec(110);
    mpf_t re2, im2;
    mpf_init(re2);
    mpf_init(im2);
    mpf_set_str(re2, re3.c_str(), 10);
    mpf_set_str(im2, im3.c_str(), 10);

    mpf_t tmp_d;
    mpf_init(tmp_d);
    mpf_set_d(tmp_d, -zoom * iWidth / scale * 2); // double will suffice as values are small
    mpf_add(re2, re2, tmp_d);
    mpf_set_d(tmp_d, zoom * iHeight / scale * 2); // double will suffice as values are small
    mpf_add(im2, im2, tmp_d);
    mpf_t tim;
    mpf_init(tim);
    mpf_t step;
    mpf_init(step);
    mpf_set_d(step, zoom / scale * 4);
    double re2hi, re2lo;
    gmp2double2(re2, tmp_d, re2hi, re2lo);
    double stephi, steplo;
    gmp2double2(step, tmp_d, stephi, steplo);
    //cout << "re2hi " << re2hi << endl;
    //cout << "step " << stephi << endl;
    //gmp_printf("The value is: %Fe\n", im2);


    // find top left corner

    //float re2 = re - zoom * iWidth / scale * 2;
    //float im2 = im + zoom * iHeight / scale * 2;
    //double imtop = im2;
    //double step = zoom / scale * 4;

    // run the function for every row by id

    for (int i = 0; i < iHeight; i++) {
        if (i % threads == id) {
            mpf_mul_ui(tim, step, i); // step*i
            mpf_sub(tim, im2, tim); // im2-step*i
            double imhi, imlo;
            gmp2double2(tim, tmp_d, imhi, imlo);
            // make row
            //cout << "GOGOGO "<<(unsigned long long)V<<' '<<i << ' ' << re2 << ' ' << im2 << ' ' << step << endl;
            makeRowdouble2(re2hi,imhi,re2lo,imlo,stephi,steplo,speclen,maxitr,V + (i * iWidth),H + (i * iWidth));
            //cout << "GOGOGO2 " << (unsigned long long)V << ' ' << i << ' ' << re2 << ' ' << im2 << ' ' << step << endl;
        }
        //im2 -= step;
        //     im2 = imtop - step * i;

    }
    mpf_clear(tmp_d);
    mpf_clear(tim);
    mpf_clear(step);
    mpf_clear(re2);
    mpf_clear(im2);
}

Mat makeFrameDouble2(string re3, string im3, double zoom, int32_t maxitr, int32_t speclen, unsigned int threads) {
    unsigned char* H = new unsigned char[iWidth * iHeight];
    unsigned char* S = new unsigned char[iWidth * iHeight](); // init to ff
    std::memset(S, 0xFF, iWidth * iHeight);
    unsigned char* V = new unsigned char[iWidth * iHeight]();
    mpf_set_default_prec(110);
    H[0] = 1;
    vector<thread> threadsV;
    for (int id = 0; id < threads; id++) {
        threadsV.emplace_back(rowThreadDouble2, re3, im3, zoom, maxitr, speclen, threads, id, H, V);
    }
    for (auto& cThread : threadsV) {
        cThread.join();
    }
    const int n = iWidth * iHeight;

    // Allocate interleaved HSV image
    cv::Mat hsv(iHeight, iWidth, CV_8UC3);

    // Get raw pointer to Mat data
    uint8_t* dst = hsv.ptr<uint8_t>(0);

    // Single tight loop, no .at<>, no branches
    for (int i = 0; i < n; ++i)
    {
        //if (i % 1000 == 0) {
            //cout << (int)H[i] << ' ' << (int)V[i] << endl;
        //}
        //dst[3 * i + 0] = H[i];
        //dst[3 * i + 1] = S[i];
        //dst[3 * i + 2] = /*0xff;*/ V[i]; //nah lets not
        if (V[i] == 0) {
            dst[3 * i + 0] = 0;
            dst[3 * i + 1] = 0;
            dst[3 * i + 2] = 0;
        }
        else {
            dst[3 * i + 0] = palette[3 * H[i]];
            dst[3 * i + 1] = palette[3 * H[i] + 1];
            dst[3 * i + 2] = palette[3 * H[i] + 2];
        }
    }

    // Convert in one vectorized call
    cv::Mat bgr;
    //cv::cvtColor(hsv, bgr, cv::COLOR_HSV2BGR_FULL);
    Mat blurred, final_glow;

    // 1. Create a heavy blur (this will be our "light bleed")
    GaussianBlur(hsv, blurred, Size(35, 35), 0);

    // 2. Blend the original with the blur
    // alpha = weight of original, beta = weight of blur, gamma = brightness offset
    // This is essentially: (src * 0.7) + (blurred * 0.3)
    addWeighted(hsv, 0.7, blurred, 0.3, 0.0, final_glow);
    // free mem
    delete[] H;
    delete[] S;
    delete[] V;
    return final_glow;
}


//extern "C" float AddFloats(float a, float b);
extern "C" void MakeRowFloat(float re, float im, float step, int maxitr, int speclen, unsigned char* H, unsigned char* V); // from MASM

void rowThreadFloat(float re, float im, float zoom, int32_t maxitr,
    int32_t speclen, unsigned int threads, int id, unsigned char* H, unsigned char* V) {

    // find top left corner

    float re2 = re - zoom * iWidth / scale * 2;
    float im2 = im + zoom * iHeight / scale * 2;
    float imtop = im2;
    float step = zoom / scale * 4;

    // run the function for every row by id

    for (int i = 0; i < iHeight; i++) {
        if (i % threads == id) {
            // make row
            //cout << "GOGOGO "<<(unsigned long long)V<<' '<<i << ' ' << re2 << ' ' << im2 << ' ' << step << endl;
            MakeRowFloat(re2, im2, step, maxitr, speclen, H + (i * iWidth), V + (i * iWidth));
            //cout << "GOGOGO2 " << (unsigned long long)V << ' ' << i << ' ' << re2 << ' ' << im2 << ' ' << step << endl;
        }
        //im2 -= step;
        im2 = imtop - step * i;
    }

}

Mat makeFrameFloat(float re, float im, float zoom, int32_t maxitr, int32_t speclen, unsigned int threads) {
    unsigned char* H = new unsigned char[iWidth * iHeight];
    unsigned char* S = new unsigned char[iWidth * iHeight](); // init to ff
    std::memset(S, 0xFF, iWidth * iHeight);
    unsigned char* V = new unsigned char[iWidth * iHeight];
    H[0] = 1;
    vector<thread> threadsV;
    for (int id = 0; id < threads; id++) {
        threadsV.emplace_back(rowThreadFloat, re, im, zoom, maxitr, speclen, threads, id, H, V);
    }
    for (auto& cThread : threadsV) {
        cThread.join();
    }
    const int n = iWidth * iHeight;

    // Allocate interleaved HSV image
    cv::Mat hsv(iHeight, iWidth, CV_8UC3);

    // Get raw pointer to Mat data
    uint8_t* dst = hsv.ptr<uint8_t>(0);

    // Single tight loop, no .at<>, no branches
    for (int i = 0; i < n; ++i)
    {
        //if (i % 1000 == 0) {
            //cout << (int)H[i] << ' ' << (int)V[i] << endl;
        //}
        //dst[3 * i + 0] = H[i];
        //dst[3 * i + 1] = S[i];
        //dst[3 * i + 2] = /*0xff;*/ V[i]; //nah lets not
        if (V[i] == 0) {
            dst[3 * i + 0] = 0;
            dst[3 * i + 1] = 0;
            dst[3 * i + 2] = 0;
        }
        else {
            dst[3 * i + 0] = palette[3*H[i]];
            dst[3 * i + 1] = palette[3 * H[i]+1];
            dst[3 * i + 2] = palette[3*H[i]+2];
        }
    }

    // Convert in one vectorized call
    cv::Mat bgr;
    //cv::cvtColor(hsv, bgr, cv::COLOR_HSV2BGR_FULL);
    Mat blurred, final_glow;

    // 1. Create a heavy blur (this will be our "light bleed")
    GaussianBlur(hsv, blurred, Size(35, 35), 0);

    // 2. Blend the original with the blur
    // alpha = weight of original, beta = weight of blur, gamma = brightness offset
    // This is essentially: (src * 0.7) + (blurred * 0.3)
    addWeighted(hsv, 0.7, blurred, 0.3, 0.0, final_glow);
    // free mem
    delete[] H;
    delete[] S;
    delete[] V;
    return final_glow;
}

extern "C" void MakeRowDouble(double re, double im, double step, int maxitr, int speclen, unsigned char* H, unsigned char* V); // from MASM

void rowThreadDouble(double re, double im, double zoom, int32_t maxitr,
    int32_t speclen, unsigned int threads, int id, unsigned char* H, unsigned char* V) {

    // find top left corner

    double re2 = re - zoom * iWidth / scale * 2;
    double im2 = im + zoom * iHeight / scale * 2;
    double imtop = im2;
    double step = zoom / scale * 4;

    // run the function for every row by id

    for (int i = 0; i < iHeight; i++) {
        if (i % threads == id) {
            // make row
            //cout << "GOGOGO "<<(unsigned long long)V<<' '<<i << ' ' << re2 << ' ' << im2 << ' ' << step << endl;
            MakeRowDouble(re2, im2, step, maxitr, speclen, H + (i * iWidth), V + (i * iWidth));
            //cout << "GOGOGO2 " << (unsigned long long)V << ' ' << i << ' ' << re2 << ' ' << im2 << ' ' << step << endl;
        }
        im2 = imtop - step * i;
        //im2 -= step;
    }

}

Mat makeFrameDouble(double re, double im, double zoom, int32_t maxitr, int32_t speclen, unsigned int threads) {
    unsigned char* H = new unsigned char[iWidth * iHeight+2];
    unsigned char* S = new unsigned char[iWidth * iHeight](); // init to ff
    std::memset(S, 0xFF, iWidth * iHeight);
    unsigned char* V = new unsigned char[iWidth * iHeight];
    H[0] = 1;
    vector<thread> threadsV;
    for (int id = 0; id < threads; id++) {
        threadsV.emplace_back(rowThreadDouble, re, im, zoom, maxitr, speclen, threads, id, H, V);
    }
    for (auto& cThread : threadsV) {
        cThread.join();
    }
    const int n = iWidth * iHeight;

    // Allocate interleaved HSV image
    cv::Mat hsv(iHeight, iWidth, CV_8UC3);

    // Get raw pointer to Mat data
    uint8_t* dst = hsv.ptr<uint8_t>(0);

    // Single tight loop, no .at<>, no branches
    for (int i = 0; i < n; ++i)
    {
        //if (i % 1000 == 0) {
            //cout << (int)H[i] << ' ' << (int)V[i] << endl;
        //}
        if (V[i] == 0) {
            dst[3 * i + 0] = 0;
            dst[3 * i + 1] = 0;
            dst[3 * i + 2] = 0;
        }
        else {
            dst[3 * i + 0] = palette[3*H[i]];
            dst[3 * i + 1] = palette[3 * H[i]+1];
            dst[3 * i + 2] = palette[3*H[i]+2];
        }
    }

    // Convert in one vectorized call
    cv::Mat bgr;
    //cv::cvtColor(hsv, bgr, cv::COLOR_HSV2BGR_FULL);
    Mat blurred, final_glow;

    // 1. Create a heavy blur (this will be our "light bleed")
    GaussianBlur(hsv, blurred, Size(35, 35), 0);

    // 2. Blend the original with the blur
    // alpha = weight of original, beta = weight of blur, gamma = brightness offset
    // This is essentially: (src * 0.7) + (blurred * 0.3)
    addWeighted(hsv, 0.7, blurred, 0.3, 0.0, final_glow);
    // free mem
    delete[] H;
    delete[] S;
    delete[] V;
    return final_glow;
}

bool activateMouse = false;
double re3 = 0, im3 = 0, zoom3 = 1, maxitr3=1000,speclen3=100;
int threadsT;
Mat image(400, 400, CV_8UC3, Scalar(0, 255, 0));
mutex imageMux;
std::atomic<bool> done(false);
std::atomic<bool> renderRunning(false);
string reSt, imSt;

void render() {
    if (renderRunning) {
        return;
    }
    cout << "speclen:" << speclen3 << endl;
    renderRunning = true;
    int targetWidth = 1280;
    int targetHeight = 720;
    cv::Mat res;// = makeFrameFloat(re3, im3, zoom3, 1000, 100, threadsT);
    if (zoom3 >= 1e-4) {
        res=makeFrameFloat(re3, im3, zoom3, maxitr3, speclen3, threadsT);
    }
    else {
        res = makeFrameDouble(re3, im3, zoom3, maxitr3, speclen3, threadsT);
        cout << "DOUBLE" << endl;
    }
    cv::Mat output;
    cv::resize(res, output, cv::Size(targetWidth, targetHeight), 0, 0, cv::INTER_NEAREST);
    // Save the result
    //cv::imwrite("output_hd.jpg", output);

    // Optionally display the image
    //cv::imshow("Downscaled HD", output);
    {
        lock_guard<mutex> guard(imageMux);
        image = output;
    }
    cout << "Rendered following params: re=" << re3 << ", im=" << im3 << ", zoom=" << zoom3 << endl;
    renderRunning = false;
}

void onMouse(int event, int x, int y, int flags, void* userdata) {
    if (event == cv::EVENT_LBUTTONDOWN) {
        // Print coordinates to console
        std::cout << "Left button clicked at: (" << x << ", " << y << ")" << std::endl;

        // Store the point
        //points.push_back(cv::Point(x, y));

        // Optional: Draw a circle on the image at the clicked location
        // The 'userdata' parameter can be used to pass the image pointer
        //if (userdata) {
        //    cv::Mat* image = static_cast<cv::Mat*>(userdata);
        //    cv::circle(*image, cv::Point(x, y), 5, cv::Scalar(0, 255, 0), -1);
        //}
        if (activateMouse) {
            cv::Rect rect = cv::getWindowImageRect("Downscaled HD");
            double xScale = ((double)x / rect.width * 2 - 1);
            double yScale = ((double)y / rect.height * 2 - 1) * rect.height / rect.width;
            re3 += xScale * zoom3*2;
            im3 -= yScale * zoom3*2;
            zoom3 *= 0.8;
            thread worker(render);
            worker.detach();
        }
    }
    // You can handle other events here (e.g., right click, mouse move)
    // else if (event == cv::EVENT_RBUTTONDOWN) { ... }
    // else if (event == cv::EVENT_MOUSEMOVE) { ... }
}
inline bool headless() { return fs::exists("headless.txt"); }
bool headed = !headless();
int main()

{
    // load dll

    HMODULE h = LoadLibraryA("mandelbrotfortran.dll");
    makeRowdouble2 = (fortrandouble2)(GetProcAddress(h, "makeRow"));

    std::ifstream inpp("palette.txt");
    string inpp2;
    inpp >> inpp2;
    std::ifstream pl(inpp2, std::ios::binary);
    pl.read(palette, 256 * 3);
    /*std::cout << "Hello World!\n";
    float res = AddFloats(1.0, 2.5);
    cout << res;*/
    // test to see if it can even make an image
    float zoom = 1.0;
    unsigned int n = std::thread::hardware_concurrency();
    std::cout << "Number of logical cores: " << n << std::endl;
    if (n == 0) n = 8;
    //n = 1;
    threadsT = n;
        // Create a 500x500 image with 3 channels (BGR)
    cv::Mat img(500, 500, CV_8UC3, cv::Scalar(255, 0, 0)); // Blue in BGR

    cv::imshow("Pure Blue", img);

    cv::waitKey(0);
    cv::destroyAllWindows();
    Mat test = makeFrameFloat(0, 0, 1, 1000, 100, n);
    cv::Mat output;
    int targetWidth = 1280;
    int targetHeight = 720;
    cv::resize(test, output, cv::Size(targetWidth, targetHeight), 0, 0, cv::INTER_NEAREST);
    /*if (headed) */cv::imshow("Downscaled HD", output);
    /*if (headed) */waitKey(1000);
    cout << "float\n";
    //test = makeFrameDouble2("-0.1038852254068171748146993282", "0.95842286222560377416121705175", 0.0000000000000000000098962695, 2500, 250, n);//makeFrameDouble(0, 0, 1, 1000, 100, n);
    //imshow("testing123", test);
    //waitKey(0);

    // Output image
    cv::namedWindow("Downscaled HD");
    // Resize using nearest neighbor
    cv::resize(test, output, cv::Size(targetWidth, targetHeight), 0, 0, cv::INTER_NEAREST);

    cv::setMouseCallback("Downscaled HD", onMouse, &test);
    // Save the result
    //cv::imwrite("output_hd.jpg", output);

    // Optionally display the image
    /*if (headed) */cv::imshow("Downscaled HD", output);
    cv::waitKey(1000);
cv::destroyAllWindows();
    int mode;
    cout << "Set mode (0 for interactive, 1 for animation): ";
    cin >> mode;
    cout << std::setprecision(std::numeric_limits<double>::max_digits10);
    switch (mode) {
    case 0:
        cout << "Interactive zooming!" << endl;
        activateMouse = true;
        render();
        while (true) {
            int k = waitKey(16);
            if (k == 'q') {
                cout << "EXITING..." << endl;
                break;
            }
            else if (k == 'o') {
                cout << "ZOOM OUT..." << endl;
                zoom3 /= 0.8;
                thread worker(render);
                worker.detach();
            }
            else if (k == 'i') {
                cout << "Max Iterations: ";
                cin >> maxitr3;
                thread worker(render);
                worker.detach();
            }
            else if (k == 's') {
                cout << "Spectrum Length: ";
                cin >> speclen3;
                thread worker(render);
                worker.detach();
            }
            else if (k == 'r') {
                cout << "RESET" << endl;
                re3 = 0, im3 = 0, zoom3 = 1, maxitr3 = 1000, speclen3 = 100;
                thread worker(render);
                worker.detach();
            }
            {
                lock_guard<mutex> guard(imageMux);
                /*if (headed) */imshow("Downscaled HD", image);
            }
        }
        break;
    case 1:
    if (!headed) destroyAllWindows();
    {
        cout << "GENERATOR!" << endl;
        double re, im, zoom;
        string reIn2, imIn2;
        cout << "Re: ";
        cin >> reIn2;
        cout << "Im: ";
        cin >> imIn2;
        re = stod(reIn2);
        im = stod(imIn2);
        cout << "Zoom: ";
        cin >> zoom;
        zoom = 1 / zoom; // fiiix
        int maxitr, speclen;
        cout << "Max Iterations (good value is 1000): ";
        cin >> maxitr;
        cout << "Spectrum Length (good value is 100): ";
        cin >> speclen;
        double imsc;
        cout << "Display scale: ";
        cin >> imsc;
        {
            string outputFile;
            cout << "Output file: ";
            cin >> outputFile;
            //std::string outputFile = "output2.avi"; // AVI container

            // Use FFV1 (lossless) codec

            auto cLambda = [&]() {
                cv::VideoWriter writer(outputFile, cv::VideoWriter::fourcc('M', 'P', '4', 'V'), 60, cv::Size(iWidth, iHeight), true);
                //writer.open(outputFile, cv::VideoWriter::fourcc('M', 'J', 'P', 'G'), 60, cv::Size(iWidth, iHeight), true);
                if (!writer.isOpened()) {
                    std::cerr << "Error: Could not open the output video file for writing\n";
                    return -1;
                }
                cout << endl;
                int frameCount = (int)std::ceil(std::log(zoom) / std::log(0.98851402035));
                int fc = 0;
                bool dd = true;
                bool dd2 = true;
                for (double cZoom = 1; cZoom >= zoom; cZoom *= 0.98851402035) {
                    cout << "Done with frames " << fc << " out of  " << frameCount << "\r" << flush;
                    fc++;
                    Mat frame;
                    if (cZoom >= 1e-4) {
                        frame = makeFrameFloat(re, im, cZoom, maxitr, speclen, threadsT);
                        //cout << '\r' << cZoom;
                    }
                    else if (cZoom >= 1e-13) {
                        frame = makeFrameDouble(re, im, cZoom, maxitr, speclen, threadsT);
                        if (dd) {
                            cout << "\nDOUBLE\n";// << cZoom;
                            dd = false;
                        }
                    }
                    else {
                        frame = makeFrameDouble2(reIn2, imIn2, cZoom, maxitr, speclen, threadsT);
                        if (dd2) {
                            cout << "\nDOUBLE-DOUBLE\n";// << cZoom;
                            dd2 = false;
                        }
                    }
                    cv::resize(frame, output, cv::Size(iWidth * imsc, iHeight * imsc), 0, 0, cv::INTER_NEAREST);
                    {
                        lock_guard<mutex> imgLock(imageMux);
                        image = output;
                    }
                    //imshow("Downscaled HD", output);
                    //waitKey(16);

                    writer.write(frame);
                }
                cout << "Done with frames " << fc << " out of  " << frameCount << "\n" << flush;
                writer.release();
                done = true;
                };

            thread worker(cLambda);
            while (!done) {
                waitKey(16);
                {
                    lock_guard<mutex> imgLock(imageMux);
                    if (headed) imshow("Downscaled HD", image);
                }
            }
        }
        break;
    }
    default:
        cout << "UNKNOWN MODE!" << endl;
        break;
    }
}

// Run program: Ctrl + F5 or Debug > Start Without Debugging menu
// Debug program: F5 or Debug > Start Debugging menu
// Debug program: F5 or Debug > Start Debugging menu

// Tips for Getting Started: 
//   1. Use the Solution Explorer window to add/manage files
//   2. Use the Team Explorer window to connect to source control
//   3. Use the Output window to see build output and other messages
//   4. Use the Error List window to view errors
//   5. Go to Project > Add New Item to create new code files, or Project > Add Existing Item to add existing code files to the project
//   6. In the future, to open this project again, go to File > Open > Project and select the .sln file
