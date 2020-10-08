//
//  SendReportsVC.swift
//  BT-Tracking
//
//  Created by Lukáš Foldýna on 11/08/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import UIKit
import Reachability
import RxSwift
import RxRelay

final class SendReportsVC: UIViewController {

    // MARK: -

    private let viewModel = SendReportsVM()

    private var code = BehaviorRelay<String>(value: "")
    private var isValid: Observable<Bool> {
        code.asObservable().map { phoneNumber -> Bool in
            InputValidation.code.validate(phoneNumber)
        }
    }
    private var keyboardHandler: KeyboardHandler!
    private var disposeBag = DisposeBag()

    private var expirationSeconds: TimeInterval = 0
    private var expirationTimer: Timer?

    private var firstAppear: Bool = true

    // MARK: - Outlets

    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var headlineLabel: UILabel!
    @IBOutlet private weak var codeTextField: UITextField!

    @IBOutlet private weak var buttonsView: ButtonsBackgroundView!
    @IBOutlet private weak var buttonsBottomConstraint: NSLayoutConstraint!
    @IBOutlet private weak var actionButton: Button!

    override func viewDidLoad() {
        super.viewDidLoad()

        codeTextField.textContentType = .oneTimeCode

        buttonsView.connect(with: scrollView)
        buttonsBottomConstraint.constant = ButtonsBackgroundView.BottomMargin

        setupTextField()
        setupStrings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if UIScreen.main.bounds.size.width == 320 {
            navigationController?.navigationBar.prefersLargeTitles = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if firstAppear {
            keyboardHandler.setup()
            codeTextField.becomeFirstResponder()
            firstAppear = false
        }
    }

    // MARK: - Actions

    @IBAction private func sendReportsAction() {
        guard let connection = try? Reachability().connection, connection != .unavailable else {
            showSendDataError()
            return
        }
        view.endEditing(true)
        verifyCode(code.value)
    }

    @IBAction private func resultAction() {
        perform(segue: StoryboardSegue.SendReports.result)
    }

    @IBAction private func closeAction() {
        dismiss(animated: true)
    }

}

extension SendReportsVC: UITextFieldDelegate {

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return validateTextChange(with: .code, textField: textField, changeCharactersIn: range, newString: string)
    }

}

private extension SendReportsVC {

    // MARK: - Setup

    func setupTextField() {
        keyboardHandler = KeyboardHandler(in: view, scrollView: scrollView, buttonsView: buttonsView, buttonsBottomConstraint: buttonsBottomConstraint)

        codeTextField.rx.text.orEmpty.bind(to: code).disposed(by: disposeBag)

        isValid.bind(to: actionButton.rx.isEnabled).disposed(by: disposeBag)
    }

    func setupStrings() {
        title = L10n.dataListSendTitle
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))

        headlineLabel.text = L10n.dataListSendHeadline
        codeTextField.placeholder = L10n.dataListSendPlaceholder
        actionButton.setTitle(L10n.dataListSendActionTitle)
    }

    // MARK: - Progress

    func reportShowProgress() {
        showProgress()

        isModalInPresentation = true
        navigationItem.setLeftBarButton(nil, animated: true)
    }

    func reportHideProgress() {
        hideProgress()

        isModalInPresentation = false
        navigationItem.setLeftBarButton(UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction)), animated: true)
    }

    // MARK: - Reports

    enum ReportType {
        case normal, test
    }

    func verifyCode(_ code: String) {
        reportShowProgress()

        AppDelegate.dependency.verification.verify(with: code) { [weak self] result in
            switch result {
            case .success(let token):
                if #available(iOS 13.7, *) {
                    self?.askIfUserIsTraveler(token: token)
                } else {
                    self?.report(with: token)
                }
            case .failure(let error):
                log("DataListVC: Failed to verify code \(error)")
                self?.reportHideProgress()
                self?.showVerifyError()
            }
        }
    }

    func report(with token: String, traveler: Bool = false) {
        #if DEBUG
        debugAskForTypeOfKeys(token: token, traveler: traveler)
        #else
        sendReport(with: .normal, token: token, traveler: traveler)
        #endif
    }

    func debugAskForTypeOfKeys(token: String, traveler: Bool) {
        let controller = UIAlertController(title: "Který druh klíčů?", message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: "Test Keys", style: .default, handler: { [weak self] _ in
            self?.sendReport(with: .test, token: token, traveler: traveler)
        }))
        controller.addAction(UIAlertAction(title: "Normal Keys", style: .default, handler: {[weak self]  _ in
            self?.sendReport(with: .normal, token: token, traveler: traveler)
        }))
        controller.addAction(UIAlertAction(title: L10n.activeBackgroundModeCancel, style: .cancel, handler: nil))
        present(controller, animated: true, completion: nil)
    }

    @available (iOS 13.7, *)
    func askIfUserIsTraveler(token: String) {
        let exposureService = AppDelegate.dependency.exposureService
        exposureService.getUserTraveled { [weak self] result in
            switch result {
            case let .success(traveler):
                self?.report(with: token, traveler: traveler)
            case let .failure(error):
                #if DEBUG
                self?.show(error: error)
                #endif
                self?.report(with: token)
            }
        }
    }

    func sendReport(with type: ReportType, token: String, traveler: Bool) {
        let verificationService = AppDelegate.dependency.verification
        let reportService = AppDelegate.dependency.reporter
        let exposureService = AppDelegate.dependency.exposureService
        let callback: ExposureServicing.KeysCallback = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let keys):
                guard !keys.isEmpty else {
                    self.reportHideProgress()
                    self.resultAction()
                    self.showNoKeysError()
                    return
                }

                do {
                    let secret = Data.random(count: 32)
                    let hmacKey = try reportService.calculateHmacKey(keys: keys, secret: secret)
                    verificationService.requestCertificate(token: token, hmacKey: hmacKey) { result in
                        switch result {
                        case .success(let certificate):
                            self.uploadKeys(keys: keys, verificationPayload: certificate, hmacSecret: secret, traveler: traveler)
                        case .failure(let error):
                            log("DataListVC: Failed to get verification payload \(error)")
                            self.reportHideProgress()
                            self.showSendDataError()
                        }
                    }
                } catch {
                    log("DataListVC: Failed to get hmac for keys \(error)")
                    self.reportHideProgress()
                    self.showSendDataError()
                }
            case .failure(let error):
                log("DataListVC: Failed to get exposure keys \(error)")
                self.reportHideProgress()

                switch error {
                case .noData:
                    self.resultAction()
                    self.showNoKeysError()
                default:
                    self.showSendDataError()
                }
            }
        }

        switch type {
        case .test:
            exposureService.getTestDiagnosisKeys(callback: callback)
        case .normal:
            exposureService.getDiagnosisKeys(callback: callback)
        }
    }

    func uploadKeys(keys: [ExposureDiagnosisKey], verificationPayload: String, hmacSecret: Data, traveler: Bool) {
        AppDelegate.dependency.reporter.uploadKeys(
            keys: keys,
            verificationPayload:
            verificationPayload,
            hmacSecret: hmacSecret,
            traveler: traveler)
        { [weak self] result in
            self?.reportHideProgress()
            switch result {
            case .success:
                self?.resultAction()
            case .failure:
                self?.showSendDataError()
            }
        }
    }

    func showVerifyError() {
        showAlert(
            title: L10n.dataListSendErrorWrongCodeTitle,
            message: L10n.dataListSendErrorWrongCodeMessage,
            okHandler: { [weak self] in
                self?.codeTextField.text = nil
                self?.codeTextField.becomeFirstResponder()
            }
        )
    }

    func showNoKeysError() {
        showAlert(title: L10n.dataListSendErrorNoKeys)
    }

    func showSendDataError() {
        showAlert(
            title: L10n.dataListSendErrorFailedTitle,
            message: L10n.dataListSendErrorFailedMessage
        )
    }

}
